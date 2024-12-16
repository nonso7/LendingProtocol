// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CuStableCoin} from "./CuStableCoin.sol";
import {AggregatorV3Interface} from "../test/mocks/AggregatorV3Interface.sol";

contract DefiProtocol {
    struct Borrow {
        uint256 amountBorrowed;
        uint256 borrowTimestamp;
        uint256 interestRate;
    }

    struct Auction {
        address liquidator;
        uint256 collateralAmount;
        uint256 startTime;
    }

    error Protocol_AmountShouldBeMoreThanZero();
    error Protocol_TokenNotOntheWishList(address token);
    error Protocol_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error Protocol_CollateralDepositeFailed();
    error Protocol_BorrowFailedTxn();
    error Protocol_UnderCollateralized();
    error Protocol_LoanRepaymentFailed();
    error Protocol_NoActiveLoan();
    error Protocol_LendTransferFailed();
    error Protocol_FeeTransferFailed();
    error Protocol_HealthFactorOk();
    error Protocol_TranferFailed();
    error Protocol_FlashLoanHasntBeenPaidBack();

    mapping(address token => address priceFeeds) _priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private _collateralDeposited;
    mapping(address user => mapping(address token => uint256 amount))
        private _tokenBorrowed;
    mapping(address => bool) private whitelistedTokens;
    mapping(address user => uint256 amount) private _CuCoinMinted;
    mapping(address user => Borrow) private loanAccumulation;
    mapping(address users => Auction) public userAuctions;
    address[] collateralTokenAddress;

    address public auctionContract; // Auction contract address
    uint256 public constant TRANSFER_FEE_PERCENTAGE = 8; // 8% fee
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    CuStableCoin private immutable i_dsCu;
    uint256 public constant COLLATERALIZATION_RATIO = 150;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 public constant REWARD_POOL_PERCENTAGE = 20;
    uint256 public constant FLASH_LOAN_INTEREST = 9;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event LoanRepaid(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    );
    event AuctionEntered(
        address indexed user,
        address indexed liquidator,
        address collateral,
        uint256 collateralAmount,
        uint256 bonus
    );
    event LoanTaken(
        address indexed borrower,
        uint256 amount,
        uint256 interestRate
    );
    event RewardPoolFunded(uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert Protocol_AmountShouldBeMoreThanZero();
        }
        _;
    }

    modifier onlyWishListedToken(address token) {
        if (!whitelistedTokens[token]) {
            revert Protocol_TokenNotOntheWishList(token);
        }
        _;
    }

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedsAddress,
        address CuCoinAddress,
        address _auctionContract
    ) {
        if (tokenAddress.length != priceFeedsAddress.length) {
            revert Protocol_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            _priceFeeds[tokenAddress[i]] = priceFeedsAddress[i];
            whitelistedTokens[tokenAddress[i]] = true;
            collateralTokenAddress.push(tokenAddress[i]);
        }
        i_dsCu = CuStableCoin(CuCoinAddress);
        auctionContract = _auctionContract;
    }

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amount
    )
        external
        moreThanZero(amount)
        onlyWishListedToken(tokenCollateralAddress)
    {
        _collateralDeposited[msg.sender][tokenCollateralAddress] -= amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Protocol_CollateralDepositeFailed();
        }
    }

    function _getAccounDetails(
        address user
    )
        private
        view
        returns (uint256 totalCuCoinMinted, uint256 collateralValeInUsd)
    {
        totalCuCoinMinted = _CuCoinMinted[user];
        collateralValeInUsd = getTotalCollateralValue(user);
    }

    function healthFactorDetails(address user) private view returns (uint256) {
        (
            uint256 totalCuCoinMinted,
            uint256 collateralValeInUsd
        ) = _getAccounDetails(user);
        return calculateHealthFactor(totalCuCoinMinted, collateralValeInUsd);
    }

    function calculateHealthFactor(
        uint256 totalCuCoinMinted,
        uint256 collateralValeInUsd
    ) internal pure returns (uint256) {
        uint256 collateralThreashold = (collateralValeInUsd *
            COLLATERALIZATION_RATIO) / LIQUIDATION_PRECISION;
        return (collateralThreashold * PRECISION) / totalCuCoinMinted;
    }

    function getTotalCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < collateralTokenAddress.length; i++) {
            address token = collateralTokenAddress[i];
            uint256 amount = _collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function _getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function borrow(
        uint256 amount,
        address tokenCollateralAddress,
        uint256 interestRate
    )
        external
        moreThanZero(amount)
        onlyWishListedToken(tokenCollateralAddress)
    {
        lendingWithFee(tokenCollateralAddress, amount);
        uint256 collateralRatio = healthFactorDetails(msg.sender);
        if (collateralRatio <= 1) {
            revert Protocol_UnderCollateralized();
        }

        Borrow storage existingLoan = loanAccumulation[msg.sender];
        if (existingLoan.amountBorrowed > 0) {
            uint256 accruedInterest = calculateInterest(
                existingLoan.amountBorrowed,
                existingLoan.interestRate,
                existingLoan.borrowTimestamp
            );

            // Update loan balance and reset timestamp
            existingLoan.amountBorrowed += accruedInterest;
            existingLoan.borrowTimestamp = block.timestamp;
        }

        bool success = IERC20(tokenCollateralAddress).transfer(
            msg.sender,
            amount
        );
        if (!success) {
            revert Protocol_BorrowFailedTxn();
        }

        emit LoanTaken(msg.sender, amount, interestRate);
    }

    function repayLoan(address tokenCollateralAddress) external {
        Borrow storage loan = loanAccumulation[msg.sender];

        // Ensure the user has an active loan
        if (loan.amountBorrowed == 0) {
            revert Protocol_NoActiveLoan();
        }

        // Calculate accrued interest
        uint256 elapsedTime = block.timestamp - loan.borrowTimestamp;
        uint256 interest = (loan.amountBorrowed *
            loan.interestRate *
            elapsedTime) / SECONDS_IN_A_YEAR;

        // Calculate total repayment (principal + interest)
        uint256 totalRepayment = loan.amountBorrowed + interest;

        // Transfer repayment from the borrower to the protocol
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            totalRepayment
        );
        if (!success) {
            revert Protocol_LoanRepaymentFailed();
        }

        // Reset loan details after repayment
        loan.amountBorrowed = 0;
        loan.borrowTimestamp = 0;
        loan.interestRate = 0;

        emit LoanRepaid(msg.sender, totalRepayment);
    }

    function calculateInterest(
        uint256 principal,
        uint256 annualRate, // Annual interest rate in basis points (e.g., 500 for 5%)
        uint256 borrowTimestamp
    ) public view returns (uint256) {
        uint256 elapsedTime = block.timestamp - borrowTimestamp; // Elapsed time in seconds
        return
            (principal * annualRate * elapsedTime) /
            (10000 * SECONDS_IN_A_YEAR);
    }

    function lendingWithFee(
        address token,
        uint256 lendingAmount
    ) public onlyWishListedToken(token) {
        uint256 fee = (lendingAmount * 8) / 100;
        uint256 amountAfterFee = lendingAmount - fee;

        // Transfer net amount to borrower
        bool transferToBorrower = IERC20(token).transfer(
            msg.sender,
            amountAfterFee
        );
        if (!transferToBorrower) {
            revert Protocol_LendTransferFailed();
        }

        // Transfer fee to auction contract
        bool transferToAuction = IERC20(token).transfer(auctionContract, fee);
        if (!transferToAuction) {
            revert Protocol_FeeTransferFailed();
        }
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function liquidate(
        address tokenCollateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) {
        uint256 startingUserHealthFactor = healthFactorDetails(user);
        if (startingUserHealthFactor >= 1) {
            revert Protocol_HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            tokenCollateral,
            debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        reedemCollateral(
            tokenCollateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );
        _enterAuction(
            user,
            msg.sender,
            tokenCollateral,
            tokenAmountFromDebtCovered,
            bonusCollateral
        );
        _fundRewardPool(tokenAmountFromDebtCovered + bonusCollateral);
        uint256 endingUserHealthFactor = healthFactorDetails(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert("Health factor did not improve");
        }
    }

    function reedemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address liquidator
    ) private {
        _collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            liquidator,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            liquidator,
            amountCollateral
        );
        if (!success) {
            revert Protocol_TranferFailed();
        }
    }

    function _enterAuction(
        address user,
        address liquidator,
        address collateral,
        uint256 collateralAmount,
        uint256 bonus
    ) internal {
        Auction storage auction = userAuctions[user];
        auction.liquidator = liquidator;
        auction.collateralAmount = collateralAmount + bonus;
        auction.startTime = block.timestamp;

        emit AuctionEntered(
            user,
            liquidator,
            collateral,
            collateralAmount,
            bonus
        );
    }

    function _fundRewardPool(uint256 amount) internal {
        uint256 rewardPool;
        rewardPool += (amount * REWARD_POOL_PERCENTAGE) / PRECISION;
        emit RewardPoolFunded(amount);
    }

    function flashLoans(
        address tokenAddress,
        uint256 amount
    ) external returns (bool) {
        require(amount > 0, "You should borrow a specific amount");
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(address(this));
        require(balanceBefore >= amount, "Not enough token in balance");
        uint256 flashLoanFee = (amount * FLASH_LOAN_INTEREST) / 1000;
        require(
            IERC20(tokenAddress).transfer(msg.sender, amount),
            "Flash loan transfer failed"
        );

        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore + flashLoanFee,
            "Flash loan hasn't been paid with interest"
        );
        return true;
    }
}
