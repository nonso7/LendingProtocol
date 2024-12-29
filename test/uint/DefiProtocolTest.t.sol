//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployCuCoin} from "../../script/DeployCuCoin.s.sol";
import {DefiProtocol} from "../../src/CuCoinContract.sol";
import {CuStableCoin} from "../../src/CuStableCoin.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract lendProtocolDefi is Test {
    DeployCuCoin deployer;
    DefiProtocol defiProtocol;
    CuStableCoin cu;
    HelperConfig config;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 COLLATERALIZATION_RATIO = 150;
    uint256 LIQUIDATION_PRECISION = 100;
    uint256 PRECISION = 1e18;
    uint256 public constant REWARD_POOL_PERCENTAGE = 20;
    uint256 public constant FLASH_LOAN_INTEREST = 9;

    uint256 totalCuCoinMinted = 100 ether;
    uint256 collateralValueInUsd = 200 ether;
    uint256 collateralValue = 100 ether;
    uint256 initialBalance = 10 ether;

    uint256 amountCollateral = 10 ether;
    address public user = address(1);

    event PollFunded(uint256 amount);
    event CollateralRedeemed(address from, address liquidator, address tokenAddress, uint256 amountCollateral);

    function setUp() public {
        deployer = new DeployCuCoin();
        (cu, defiProtocol, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
    }

    address[] public tokenAddress;
    address[] public priceFeedAddress;
    address public auctionContract = address(4);

    ///constructor test

    function test_testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(btcUsdPriceFeed);
        priceFeedAddress.push(ethUsdPriceFeed);

        vm.expectRevert(DefiProtocol.Protocol_TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DefiProtocol(tokenAddress, priceFeedAddress, address(cu), auctionContract);
    }

    function test_priceFeedsAddressCorresponds() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        priceFeedAddress.push(ethUsdPriceFeed);
        priceFeedAddress.push(btcUsdPriceFeed);

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            if (tokenAddress[i] == priceFeedAddress[i]) {
                assertEq(tokenAddress[i], priceFeedAddress[i], "Token address does not match price feed address");
            }
        }
    }

    function testGetTokenAmountFromUsd() public view {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = defiProtocol.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function test_testGetUsdValue() public view {
        uint256 ethAmount = 15 ether; // 15e18;

        uint256 expectedUsd = (ethAmount * config.ETH_USD_PRICE()) / (10 ** config.DECIMALS());
        uint256 actualUsd = defiProtocol._getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test_testRevertIfCollateralIsZero() public {
        vm.prank(user);
        ERC20Mock(weth).approve(address(defiProtocol), amountCollateral);

        vm.expectRevert(DefiProtocol.Protocol_AmountShouldBeMoreThanZero.selector);
        defiProtocol.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("SU", "SU", user, 100e18);
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(DefiProtocol.Protocol_TokenNotOntheWishList.selector, address(randomToken))
        );

        defiProtocol.depositCollateral(address(randomToken), amountCollateral);
        vm.stopPrank();
    }



    function test_testIfCollateralWasDeposited() public {
        // Set up initial state
        ERC20Mock(weth).mint(user, amountCollateral); // Mint WETH to the user
        vm.startPrank(user); // Simulate the user calling the contract
        console.log("minted amount to user:", ERC20Mock(weth).balanceOf(user));
        // Approve the contract to spend WETH on behalf of the user
        console.log("User balance before deposit:", IERC20(weth).balanceOf(user));
        ERC20Mock(weth).approve(address(defiProtocol), 5 ether);

        // Deposit collateral
        defiProtocol.depositCollateral(address(weth), 5 ether);

        // Log the user's balance after deposit
        console.log("User balance after deposit:", IERC20(weth).balanceOf(user));

        // Log the collateral deposited by the user
        console.log("Collateral deposited by user:", defiProtocol.getCollateralDeposited(user, address(weth)));

        vm.stopPrank();
        // Check that collateral was added correctly
        assertEq(defiProtocol.getCollateralDeposited(user, address(weth)), 5 ether);
    }

    function test_testgetAccountAndHealthFactorDetails() public {
        (totalCuCoinMinted, collateralValue) = defiProtocol.getAccountDetails(user);
        assertEq(totalCuCoinMinted, collateralValue);
    }

    function test_testCalculateHealthFactor() public  view{
        uint256 collateralThreshold = (collateralValueInUsd * COLLATERALIZATION_RATIO) / LIQUIDATION_PRECISION;
        uint256 expectedHealthFactor = (collateralThreshold * PRECISION) / totalCuCoinMinted;

        uint256 actualHealthFactor = defiProtocol.getcalculateHealthFactor(totalCuCoinMinted, collateralValueInUsd);
        assertEq(actualHealthFactor, expectedHealthFactor, "Health factor calculation is in-correct");
    }

    function test_getTotalCollateralValue() public {
        // Initialize collateral addresses
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);

        uint256 ethAmount = 15 ether; // Example token amount BTC_USD_PRICE
        uint256 usdValueToken1 = (ethAmount * config.ETH_USD_PRICE()); // Mock USD value for WETH
        uint256 usdValueToken2 = (ethAmount * config.BTC_USD_PRICE()); // Mock USD value for WBTC

        console.log("usdValueToken1", usdValueToken1);
        console.log("usdValueToken2", usdValueToken2);
        // Setup `_collateralDeposited` for the user
        defiProtocol.setCollateralDeposited(user, weth, ethAmount);
        defiProtocol.setCollateralDeposited(user, wbtc, ethAmount);

        uint256 actualUsd1 = defiProtocol._getUsdValue(weth, ethAmount);
        uint256 actualUsd2 = defiProtocol._getUsdValue(wbtc, ethAmount);

        uint256 expectedTotalCollateralValue = actualUsd1 + actualUsd2;
        console.log("expectedTotalCollateralValue", expectedTotalCollateralValue);
        // Actual total collateral value
        uint256 actualTotalCollateralValue = defiProtocol.getTotalCollateralValue(user);
        console.log("actualTotalCollateralValue", actualTotalCollateralValue);
        // Assertion
        assertEq(expectedTotalCollateralValue, actualTotalCollateralValue);
    }

    function test_enterAuction() public {
        address liquidator = address(2);
        uint256 collateralAmount = 15 ether;
        uint256 bonus = 10;

        defiProtocol.enterAuctionForTesting(user, liquidator, weth, collateralAmount, bonus);

        (address storedLiquidator, uint256 storedCollateralAmount, uint256 storedStartingTime) =
            defiProtocol.getAuctionDetails(user);

        assertEq(storedLiquidator, liquidator, "Liquidator address is incorrect");
        assertEq(storedCollateralAmount, collateralAmount + bonus, "Collateral amount is incorrect");
        assertGt(storedStartingTime, 0, "Start time is not set");
    }

    function test_testFundRewardPool() public {
        uint256 rewards;
        // uint256 initialBalance = 10 ether;
        uint256 amount = 2 ether;
        vm.deal(user, initialBalance);
        vm.prank(user);
        rewards += (amount * REWARD_POOL_PERCENTAGE) / PRECISION;

        defiProtocol.fundRewardPoolForTesting(amount);
        vm.stopPrank();
        emit PollFunded(amount);
    }



    function test_testReedemCollateral() public {
        address liquidator = address(3); 
        uint256 collateralAmount = 5 ether;
        uint256 depositedCollateral = 5 ether;

        ERC20Mock(weth).mint(user, amountCollateral);
        vm.deal(user, initialBalance);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(defiProtocol), depositedCollateral);
        defiProtocol.depositCollateral(address(weth), depositedCollateral);


        defiProtocol.testReedemCollateral(weth, depositedCollateral, user, liquidator);
        vm.stopPrank();

        
        emit CollateralRedeemed(msg.sender, liquidator, wbtc, collateralAmount);
    }

    function test_testLendingWithFee() public {
        address borrower = msg.sender;
        uint256 lendingAmount = 8 ether;
        uint256 lendingFee = (lendingAmount * 8) / 100;
        uint256 amountLended = lendingAmount - lendingFee;

        
        defiProtocol.setAuctionContract(auctionContract);
        ERC20Mock(weth).mint(address(defiProtocol), 10e18);
        console.log("balance of weth minted to the defi Protocol:", ERC20Mock(weth).balanceOf(address(defiProtocol)));
        vm.prank(address(defiProtocol));
        ERC20Mock(weth).approve(address(defiProtocol), amountLended);
        

        vm.startPrank(borrower);
        defiProtocol.lendingWithFee(weth, amountLended);
        
        vm.stopPrank();
        
    }

    //     function testRevertsIfMintFails() public {
    //     // Arrange - Setup
    //     MockFailedMintDSC mockDsc = new MockFailedMintDSC();
    //     tokenAddresses = [weth];
    //     feedAddresses = [ethUsdPriceFeed];
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
    //     mockDsc.transferOwnership(address(mockDsce));
    //     // Arrange - User
    //     vm.startPrank(user);
    //     ERC20Mock(weth).approve(address(mockDsce), amountCollateral);

    //     vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
    //     mockDsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
    //     vm.stopPrank();
    // }

    // function test_testFlashLoans() public {
    //     uint256 amount = 5 ether;
    //     uint256 balanceBefore = ERC20Mock(weth).balanceOf(address(defiProtocol));
    //     uint256 balanceAfter = ERC20Mock(weth).balanceOf(address(defiProtocol));
    //     uint256 flashLoanFee = (amount * FLASH_LOAN_INTEREST) / 100;
    //     uint256 repaymentAmount = amount + flashLoanFee;

    //     ERC20Mock(weth).mint(address(defiProtocol), 10e18);
    //     vm.prank(user);
    //     ERC20Mock(weth).approve(address(defiProtocol), amount);
    //     defiProtocol.flashLoans(weth, amount);
    //     vm.stopPrank();
        
    //     assertEq(amount, 0, "You should borrow a specific amount");
    //     assertLt(balanceBefore >= amount, "Not enough token in balance");
    //     assert(balanceBefore - amount + repaymentAmount, balanceAfter, balance, "Flash loan hasnt been paid with interest");
        
    // }

//     function test_testFlashLoans() public {
//     uint256 amount = 5 ether;
//     uint256 flashLoanFee = (amount * FLASH_LOAN_INTEREST) / 1000;
//     uint256 totalRepayment = amount + flashLoanFee;

//     // Step 1: Arrange - Mint tokens to protocol
//     ERC20Mock(weth).mint(address(defiProtocol), 10 ether);

//     // Assert initial balance of protocol
//     uint256 balanceBefore = ERC20Mock(weth).balanceOf(address(defiProtocol));
//     //assert(balanceBefore >= amount, "Protocol does not have enough tokens to lend");

//     // Step 2: Arrange - Mock borrower repayment with interest
//     ERC20Mock(weth).mint(user, totalRepayment);
//     uint256 borrowerBalanceBefore = ERC20Mock(weth).balanceOf(user);
//     assertEq(borrowerBalanceBefore, totalRepayment, "Borrower mint failed");

//     // Step 3: Act - Prank borrower to approve and take a flash loan
//     vm.startPrank(user);
//     ERC20Mock(weth).approve(address(defiProtocol), totalRepayment);

//     // Assert approval is correctly set
//     uint256 allowance = ERC20Mock(weth).allowance(user, address(defiProtocol));
//     assertEq(allowance, totalRepayment, "Allowance mismatch");

//     // Borrower takes the flash loan
//     defiProtocol.flashLoans(weth, amount);
//     vm.stopPrank();

//     // Step 4: Assert - Validate protocol balances
//     uint256 balanceAfter = ERC20Mock(weth).balanceOf(address(defiProtocol));
//     assertEq(balanceAfter, balanceBefore - amount + totalRepayment, "Flash loan repayment failed");

//     // Assert borrower balance after loan
//     uint256 borrowerBalanceAfter = ERC20Mock(weth).balanceOf(user);
//     assertEq(borrowerBalanceAfter, 0, "Borrower did not repay loan properly");
// }


}
