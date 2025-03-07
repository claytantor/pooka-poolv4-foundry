// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
// import {PoolModifyPositionTest} from "v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";
import {Currency} from "v4-core/types/Currency.sol";
import "forge-std/console.sol";

contract DeployUniswapV4 is Script {
    // Deploy all core contracts and test helpers
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // create a pool manager
        PoolManager poolManager = new PoolManager(address(this));

        PoolSwapTest swapRouter = new PoolSwapTest(
            IPoolManager(address(poolManager))
        );

        PoolDonateTest donateRouter = new PoolDonateTest(
            IPoolManager(address(poolManager))
        );

        vm.stopBroadcast();

        // Log addresses for frontend use
        console.log("PoolManager address: ", address(poolManager));
        console.log("SwapRouter: ", address(swapRouter));
        console.log("DonateRouter: ", address(donateRouter));
    }
}
