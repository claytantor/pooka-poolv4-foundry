// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract LiquidityProvider is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        address user;
        IERC20 token0;
        IERC20 token1;
        uint256 amount0;
        uint256 amount1;
        PoolKey poolKey;
        IPoolManager.ModifyLiquidityParams params;
    }

    mapping(bytes32 => CallbackData) public callbackDataStore;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function modifyLiquidity(
        PoolKey memory poolKey,
        IPoolManager.ModifyLiquidityParams memory params,
        uint256 amount0,
        uint256 amount1
    ) external {
        bytes32 callbackKey = keccak256(abi.encode(poolKey, params));

        // Store callback data first
        callbackDataStore[callbackKey] = CallbackData({
            user: msg.sender,
            token0: IERC20(Currency.unwrap(poolKey.currency0)),
            token1: IERC20(Currency.unwrap(poolKey.currency1)),
            amount0: amount0,
            amount1: amount1,
            poolKey: poolKey,
            params: params
        });
    }

    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Unauthorized");

        // Retrieve stored data
        bytes32 callbackKey = abi.decode(rawData, (bytes32));
        CallbackData memory cbData = callbackDataStore[callbackKey];

        // Transfer tokens to PoolManager
        cbData.token0.transferFrom(
            cbData.user,
            address(poolManager),
            cbData.amount0
        );
        cbData.token1.transferFrom(
            cbData.user,
            address(poolManager),
            cbData.amount1
        );

        // Directly call modifyLiquidity on PoolManager
        poolManager.modifyLiquidity(
            cbData.poolKey,
            cbData.params,
            abi.encode(callbackKey)
        );

        // Clear storage
        delete callbackDataStore[callbackKey];

        return "";
    }
}
