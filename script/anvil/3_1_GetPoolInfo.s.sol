// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {PositionManager} from "v4-periphery/PositionManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract GetPoolInfo is Script {
    using PoolIdLibrary for PoolKey;

    struct PoolInfo {
        bool initialized;
        uint128 liquidity;
        int24 currentTick;
        uint160 sqrtPriceX96;
        uint256 feeGrowthGlobal0;
        uint256 feeGrowthGlobal1;
    }

    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;

    function run() external view {
        // Load pool manager address from environment
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        IPoolManager poolManager = IPoolManager(poolManagerAddress);

        // hook contract
        address hookContractAddress = vm.envAddress("POOKA_HOOK_ADDRESS");
        IHooks hookContract = IHooks(hookContractAddress);

        address dai = vm.envAddress("DAI_ADDRESS");
        address pooka = vm.envAddress("POOKA_ADDRESS");

        Currency currency0;
        Currency currency1;
        address token0Address;
        address token1Address;

        // With this (sort tokens by address):
        if (dai < pooka) {
            currency0 = Currency.wrap(dai);
            token0Address = dai;
            currency1 = Currency.wrap(pooka);
            token1Address = pooka;
        } else {
            currency0 = Currency.wrap(pooka);
            token0Address = pooka;
            currency1 = Currency.wrap(dai);
            token1Address = dai;
        }

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        PoolId poolId = poolKey.toId();

        // Get slot0 data (price/tick)
        (uint160 sqrtPriceX96, int24 currentTick, , ) = StateLibrary.getSlot0(
            poolManager,
            poolId
        );

        // Get liquidity
        uint128 liquidity = StateLibrary.getLiquidity(poolManager, poolId);

        // Get fee growth
        (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1) = StateLibrary
            .getFeeGrowthGlobals(poolManager, poolId);

        PoolInfo memory info = PoolInfo({
            initialized: sqrtPriceX96 != 0,
            liquidity: liquidity,
            currentTick: currentTick,
            sqrtPriceX96: sqrtPriceX96,
            feeGrowthGlobal0: feeGrowthGlobal0,
            feeGrowthGlobal1: feeGrowthGlobal1
        });

        // Log results for easy viewing
        console.log("Pool Initialized:", info.initialized);
        console.log("Current Liquidity:", info.liquidity);
        console.log("Current Tick:", info.currentTick);
        console.log("sqrtPriceX96:", info.sqrtPriceX96);
        console.log("Fee Growth 0:", info.feeGrowthGlobal0);
        console.log("Fee Growth 1:", info.feeGrowthGlobal1);
    }
}
