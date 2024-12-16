//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployCuCoin} from "../script/DeployCuCoin.s.sol";
import {DefiProtocol} from "../src/CuCoinContract.sol";
import {CuStableCoin} from "../src/CuStableCoin.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
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

    function setUp() public {
        deployer = new DeployCuCoin();
        (cu, defiProtocol, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();


            MockV3Aggregator mockAggregator = new MockV3Aggregator(3000 * 10**8); // $3000
    ethUsdPriceFeed = address(mockAggregator);

    // Update the protocol with the correct mock price feed
    defiProtocol.setPriceFeed(weth, ethUsdPriceFeed);
    }



    function test_testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 300000e18;
        uint256 actualUsd = defiProtocol._getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }
}