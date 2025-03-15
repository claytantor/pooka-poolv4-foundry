// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/console.sol";

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
        address token0;
        address token1;
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
        // bytes32 callbackKey = keccak256(abi.encode(poolKey, params));

        // Store callback data first
        // callbackDataStore[callbackKey] = CallbackData({
        //     user: msg.sender,
        //     token0: IERC20(Currency.unwrap(poolKey.currency0)),
        //     token1: IERC20(Currency.unwrap(poolKey.currency1)),
        //     amount0: amount0,
        //     amount1: amount1,
        //     poolKey: poolKey,
        //     params: params
        // });

        poolManager.unlock(
            abi.encode(
                CallbackData(
                    msg.sender,
                    Currency.unwrap(poolKey.currency0),
                    Currency.unwrap(poolKey.currency1),
                    amount0,
                    amount1,
                    poolKey,
                    params
                )
            )
        );
    }

    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Unauthorized");

        // Retrieve stored data
        CallbackData memory cbData = abi.decode(rawData, (CallbackData));

        console.log("Unlocking callback for user: ", cbData.user);

        IERC20 token0 = IERC20(cbData.token0);
        IERC20 token1 = IERC20(cbData.token1);

        // Transfer tokens to PoolManager
        token0.transferFrom(cbData.user, address(poolManager), cbData.amount0);
        token1.transferFrom(cbData.user, address(poolManager), cbData.amount1);

        // Directly call modifyLiquidity on PoolManager
        poolManager.modifyLiquidity(
            cbData.poolKey,
            cbData.params,
            new bytes(0)
        );

        return "";
    }

    // function modifyLiquidity(
    //     PoolKey memory poolKey,
    //     IPoolManager.ModifyLiquidityParams memory params,
    //     uint256 amount0,
    //     uint256 amount1
    // ) external {
    //     bytes32 callbackKey = keccak256(
    //         abi.encode(poolKey, params, msg.sender)
    //     );

    //     callbackDataStore[callbackKey] = CallbackData({
    //         user: msg.sender,
    //         token0: IERC20(Currency.unwrap(poolKey.currency0)),
    //         token1: IERC20(Currency.unwrap(poolKey.currency1)),
    //         amount0: amount0,
    //         amount1: amount1,
    //         poolKey: poolKey,
    //         params: params
    //     });

    //     // Initiate the liquidity modification on PoolManager
    //     poolManager.modifyLiquidity(poolKey, params, abi.encode(callbackKey));
    // }

    // function unlockCallback(
    //     bytes calldata rawData
    // ) external returns (bytes memory) {
    //     require(msg.sender == address(poolManager), "Unauthorized");

    //     bytes32 callbackKey = abi.decode(rawData, (bytes32));
    //     CallbackData memory cbData = callbackDataStore[callbackKey];

    //     // Transfer tokens to PoolManager
    //     cbData.token0.transferFrom(
    //         cbData.user,
    //         address(poolManager),
    //         cbData.amount0
    //     );
    //     cbData.token1.transferFrom(
    //         cbData.user,
    //         address(poolManager),
    //         cbData.amount1
    //     );

    //     // Clear storage
    //     delete callbackDataStore[callbackKey];

    //     return "";
    // }
}
