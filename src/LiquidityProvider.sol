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
        //log amounts
        console.log("Amount0: ", cbData.amount0);
        console.log("Amount1: ", cbData.amount1);

        IERC20 token0 = IERC20(cbData.token0);
        IERC20 token1 = IERC20(cbData.token1);

        // token0.approve(address(cbData.user), cbData.amount0);
        // token1.approve(address(cbData.user), cbData.amount1);

        // Log allowances for debugging
        uint256 allowance0Pool = token0.allowance(
            address(cbData.user),
            address(poolManager)
        );
        uint256 allowance1Pool = token1.allowance(
            address(cbData.user),
            address(poolManager)
        );
        console.log("LPUser Token0 allowance to PoolManager:", allowance0Pool);
        console.log("LPUser Token1 allowance to PoolManager:", allowance1Pool);

        // Transfer tokens to PoolManager
        token0.transferFrom(cbData.user, address(poolManager), cbData.amount0);
        token1.transferFrom(cbData.user, address(poolManager), cbData.amount1);

        poolManager.settle();
        // poolManager.settleFor(Currency.unwrap(cbData.poolKey.currency1));

        // Directly call modifyLiquidity on PoolManager
        poolManager.modifyLiquidity(
            cbData.poolKey,
            cbData.params,
            new bytes(0)
        );

        // return "";
        return bytes("");
    }
}
