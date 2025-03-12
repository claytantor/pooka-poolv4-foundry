// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {PositionManager} from "v4-periphery/PositionManager.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {IPositionDescriptor} from "v4-periphery/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/interfaces/external/IWETH9.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

import "forge-std/console.sol";

// test utils
import {DeployPermit2} from "../../test/utils/DeployPermit2.sol";

contract DeployUniswapV4 is Script, DeployPermit2 {
    // Deploy all core contracts and test helpers
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // create a pool manager
        PoolManager poolManager = new PoolManager(address(this));

        // deploy position manager
        IAllowanceTransfer permit2 = anvilPermit2();
        PositionManager posm = new PositionManager(
            poolManager,
            permit2,
            300_000,
            IPositionDescriptor(address(0)),
            IWETH9(address(0))
        );

        // create routers
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(
                IPoolManager(address(poolManager))
            );

        PoolSwapTest swapRouter = new PoolSwapTest(
            IPoolManager(address(poolManager))
        );

        PoolDonateTest donateRouter = new PoolDonateTest(
            IPoolManager(address(poolManager))
        );

        vm.stopBroadcast();

        // Log addresses for frontend use
        console.log("PoolManager: ", address(poolManager));
        console.log("SwapRouter: ", address(swapRouter));
        console.log("DonateRouter: ", address(donateRouter));
        console.log("PositionManager: ", address(posm));
        console.log("ModifyLiquidityRouter: ", address(modifyLiquidityRouter));
    }
}
