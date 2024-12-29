// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {CuStableCoin} from "../src/CuStableCoin.sol";
import {DefiProtocol} from "../src/CuCoinContract.sol";

import {console} from "forge-std/Script.sol";

contract DeployCuCoin is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    // address initialOwner;
    address auctionContract;

    function run() external returns (CuStableCoin, DefiProtocol, HelperConfig) {
        HelperConfig config = new HelperConfig(); // This comes with our mocks!

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        // console.log("weth", weth);
        // console.log("wbtc", wbtc);

        // console.log("wethUsdPriceFeed", wethUsdPriceFeed);
        // console.log("wbtcUsdPriceFeed", wbtcUsdPriceFeed);

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployer);
        CuStableCoin cu = new CuStableCoin(deployer);
        DefiProtocol cud = new DefiProtocol(tokenAddresses, priceFeedAddresses, address(cu), auctionContract);

        // cu.transferOwnership(initialOwner);
        // initialOwner = msg.sender; // address(this)
        vm.stopBroadcast();
        return (cu, cud, config);
    }
}
