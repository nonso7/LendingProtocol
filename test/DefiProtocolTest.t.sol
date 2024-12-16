//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployCuCoin} from "../script/DeployCuCoin.s.sol";
import {DefiProtocol} from "../src/CuCoinContract.sol";
import {CuStableCoin} from "../src/CuStableCoin.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "../script/HelperConfig.sol";

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

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config
            .activeNetworkConfig();

        address deployerAddress = vm.addr(deployerKey);

        console.log("Expected Owner Address:", vm.addr(deployerKey));
        console.log("Actual Owner Address:", cu.owner());

        assertEq(
            deployerAddress,
            cu.owner(),
            "Deployer is not the owner of CuStableCoin"
        );

        // Set the caller to the deployer for subsequent actions
        // vm.prank(deployerAddress);
    }

    function test_testGetUsdValue() public {
        uint256 ethAmount = 15 ether; // 15e18;

        uint256 expectedUsd = (ethAmount * config.ETH_USD_PRICE()) /
            (10 ** config.DECIMALS());

        vm.prank(vm.addr(deployerKey));

        uint256 actualUsd = defiProtocol._getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }
}
