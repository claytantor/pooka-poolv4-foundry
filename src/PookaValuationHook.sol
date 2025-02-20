// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// lib/v4-core/src/interfaces/IHooks.sol
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/base/hooks/BaseHook.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PookaToken} from "./PookaToken.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "v4-core/interfaces/IPoolManager.sol";
import "forge-std/console.sol";

/// @title PookaValuationHook
/// @notice A sample hook that triggers a buyback on the warchest pool if the designated AI agent’s swap produces profit.
contract PookaValuationHook is BaseHook, Ownable {
    /// The designated AI agent address.
    /// Token interfaces.
    IERC20 public immutable DAI;
    PookaToken public immutable POOKA;

    uint256 public externalWarchest; // DAI balance owned by the pool owner for external trading

    error OnlyOwner();
    error InvalidSwap();

    constructor(
        IPoolManager _poolManager,
        address _dai,
        address _pooka
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        DAI = IERC20(_dai);
        POOKA = PookaToken(_pooka);
    }

    // --- Core Price Adjustment Mechanism ---
    function adjustWarchest(
        PoolKey calldata key,
        bool addToPool, // true = deposit profits, false = withdraw losses
        uint256 daiAmount
    ) external onlyOwner {
        require(
            ((Currency.unwrap(key.currency0) == _getDAIAddress() &&
                Currency.unwrap(key.currency1) == _getPookaAddress()) ||
                (Currency.unwrap(key.currency1) == _getDAIAddress() &&
                    Currency.unwrap(key.currency0) == _getPookaAddress())), // Ensure order doesn't matter
            "Invalid pool key: token pair mismatch"
        );

        if (addToPool) {
            // Owner adds DAI to pool (increases POOKA value)
            _executePrivilegedSwap(
                key,
                true, // DAI -> POOKA
                daiAmount
            );
            externalWarchest -= daiAmount;
        } else {
            // Owner withdraws DAI from pool (decreases POOKA value)
            _executePrivilegedSwap(
                key,
                false, // POOKA -> DAI
                daiAmount
            );
            externalWarchest += daiAmount;
        }
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) public view override returns (bytes4, BeforeSwapDelta, uint24) {
        if (hookData.length == 0) revert InvalidSwap(); // If there is no hookData, revert

        // Extract user address from hookData
        address user = abi.decode(hookData, (address));

        // If there is hookData but not in the format we're expecting and user address is zero, revert
        if (user == address(0)) revert InvalidSwap();

        // Apply different logic for owner vs regular users
        if (user == owner()) {
            console.log("Owner swap");
            return _handleOwnerSwap(key, params);
        }
        console.log("User swap");
        return _handleUserSwap(key, params);
    }

    // --- Internal Functions ---
    function _executePrivilegedSwap(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amount
    ) internal {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amount),
            sqrtPriceLimitX96: zeroForOne
                ? TickMath.MIN_SQRT_PRICE + 1
                : TickMath.MIN_SQRT_PRICE - 1
        });

        poolManager.swap(key, params, "");
    }

    function _getDAIAddress() internal view returns (address) {
        return address(DAI);
    }

    function _getPookaAddress() internal view returns (address) {
        return address(POOKA);
    }

    function _handleOwnerSwap(
        PoolKey calldata /*key*/,
        IPoolManager.SwapParams calldata /*params*/
    ) internal pure returns (bytes4, BeforeSwapDelta, uint24) {
        // Owner swaps bypass fees and price limits
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0 // 0% swap fee
        );
    }

    function _handleUserSwap(
        PoolKey calldata /*key*/,
        IPoolManager.SwapParams calldata /*params*/
    ) internal pure returns (bytes4, BeforeSwapDelta, uint24) {
        // Regular users pay standard 0.3% fee
        console.log("_handleUserSwap User swap fee will be applied");
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            3000 // 0.3% fee
        );
    }
}
