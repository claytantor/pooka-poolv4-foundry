// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

contract TickGetter {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function getCurrentTick(
        PoolKey memory poolKey
    ) public view returns (int24 currentTick) {
        // 1. Convert PoolKey to PoolId
        PoolId poolId = poolKey.toId();

        // 2. Get slot0 data using StateLibrary
        (, currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
    }
}
