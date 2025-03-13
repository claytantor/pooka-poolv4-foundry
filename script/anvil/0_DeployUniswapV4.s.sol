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
        // POOL_MANAGER_ADDRESS=0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690
        // SWAP_ROUTER_ADDRESS=0xa82fF9aFd8f496c3d6ac40E2a0F282E47488CFc9
        // DONATE_ROUTER_ADDRESS=0x1613beB3B2C4f22Ee086B2b38C1476A3cE7f78E8
        // POSITION_MANAGER_ADDRESS=0x84eA74d481Ee0A5332c457a4d796187F6Ba67fEB
        // MODIFY_LIQUIDITY_ROUTER_ADDRESS=0x9E545E3C0baAB3E08CdfD552C960A1050f373042
        console.log("POOL_MANAGER_ADDRESS=", address(poolManager));
        console.log("SWAP_ROUTER_ADDRESS=", address(swapRouter));
        console.log("DONATE_ROUTER_ADDRESS=", address(donateRouter));
        console.log("POSITION_MANAGER_ADDRESS=", address(posm));
        console.log(
            "MODIFY_LIQUIDITY_ROUTER_ADDRESS=",
            address(modifyLiquidityRouter)
        );
    }
}
