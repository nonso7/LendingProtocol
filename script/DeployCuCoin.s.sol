// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {CuStableCoin} from "../src/CuStableCoin.sol";
import {DefiProtocol} from "../src/CuCoinContract.sol";

contract DeployCuCoin is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address initialOwner;
    address auctionContract;

    function run() external returns (CuStableCoin, DefiProtocol, HelperConfig) {
        HelperConfig config = new HelperConfig(); // This comes with our mocks!

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, ) =
        config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        CuStableCoin cu = new CuStableCoin(address(this));
        DefiProtocol cud = new DefiProtocol(tokenAddresses, priceFeedAddresses, address(cu), auctionContract);

        cu.transferOwnership(initialOwner);
        vm.stopBroadcast();
        return (cu, cud, config);
    }
}
