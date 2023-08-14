// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DSCPool} from "../src/DSCPool.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() public returns (DecentralisedStableCoin dsc, DSCEngine engine, DSCPool pool, HelperConfig config) {
        config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        dsc = new DecentralisedStableCoin();
        pool = new DSCPool();
        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc), address(pool));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
    }
}
