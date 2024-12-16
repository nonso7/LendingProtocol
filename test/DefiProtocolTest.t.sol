//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployCuCoin} from "../script/DeployCuCoin.s.sol";
import {DefiProtocol} from "../src/CuCoinContract.sol";
import {CuStableCoin} from "../src/CuStableCoin.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {HelperConfig} from "../script/HelperConfig.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

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

    uint256 amountCollateral = 10 ether;
    address public user = address(1);

    

    function setUp() public {
        deployer = new DeployCuCoin();
        (cu, defiProtocol, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

    }

    address[] public tokenAddress;
    address[] public priceFeedAddress;
    address auctionContract;

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
            if(tokenAddress[i] == priceFeedAddress[i]) {
                 assertEq(tokenAddress[i], priceFeedAddress[i], "Token address does not match price feed address");
            }
           
        }
    }

    // function test_WishListedTokenHasBeenAdded() public {
    //     for (uint256 i = 0; i < tokenAddress.length; i++) {
    //         bool wishedToken = DefiProtocol.whitelistedTokens[tokenAddress[i]];
    //         assertTrue(wishedToken, "should be listed");

    //          new DefiProtocol(tokenAddress, priceFeedAddress, address(cu), auctionContract);
    //     }
        
    // }

    function testGetTokenAmountFromUsd() public view {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = defiProtocol.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function test_testGetUsdValue() public view {
        uint256 ethAmount = 15 ether; // 15e18;

        uint256 expectedUsd = (ethAmount * config.ETH_USD_PRICE()) /
            (10 ** config.DECIMALS());
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
        ERC20Mock randomToken = new ERC20Mock("SU","SU", user, 100e18);
        vm.startPrank(user);
        
        vm.expectRevert(abi.encodeWithSelector(DefiProtocol.Protocol_TokenNotOntheWishList.selector, address(randomToken)));
        
        defiProtocol.depositCollateral(address(randomToken), amountCollateral);
        vm.stopPrank();
    }

    // modifier depositedCollateral() {
    //     ERC20Mock wethToken = ERC20Mock(weth);
    //     uint256 initialBalance = 20 ether;
    //     wethToken.mint(user, initialBalance);
    //     vm.startPrank(user);

    //     uint256 userBalance = ERC20Mock(weth).balanceOf(user);
    //     console.log(userBalance);
    //     require(userBalance >= amountCollateral, "Insufficient user balance");

    //     wethToken.approve(address(defiProtocol), amountCollateral);
    //     console.log(userBalance);
    //     defiProtocol.depositCollateral(weth, amountCollateral);
    //     vm.stopPrank();
    //     _;
    // }

    // function test_testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral{
    //     (uint256 totalDscMinted, uint256 collateralValueInUsd) = defiProtocol.getAccountDetails(user);

    //     assertEq(totalDscMinted, 0);

    //     uint256 expectedDepositedAmount = defiProtocol.getTokenAmountFromUsd(weth, collateralValueInUsd);
    //     //assertEq(totalDscMinted, 0);
    //     assertEq(expectedDepositedAmount, amountCollateral);
    // }
}