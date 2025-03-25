// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// lib/v4-core/src/interfaces/IHooks.sol
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/utils/BaseHook.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PookaToken} from "./PookaToken.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

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

    uint24 public constant INITIAL_FEE = 3000; // 0.3%
    uint24 public constant FEE_REDUCTION_PER_STEP = 150; // 5% of 3000
    uint256 public constant VOLUME_STEP = 1_000 * 1e18; // 10k POOKA tokens

    // total POOKA swapped in the pool
    uint256 public totalPookaSwapped;

    // Track positions of POOKA holders
    struct Position {
        uint256 pookaAmount;
    }

    mapping(address => Position[]) public userPositions;

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

    function getUserFee(address user) public view returns (uint24) {
        Position[] storage positions = userPositions[user];

        console.log("User: %s", user);
        console.log("Positions: %d", positions.length);
        // If no positions exist, return the initial fee (or another default value)
        if (positions.length == 0) {
            return uint24(INITIAL_FEE);
        }

        uint256 steps = positions[0].pookaAmount / VOLUME_STEP;
        console.log("Steps: %d", steps);
        console.log("Pooka amount: %d", positions[0].pookaAmount);
        steps = steps > 10 ? 10 : steps; // Max 10 steps

        uint256 feeReduction = steps * FEE_REDUCTION_PER_STEP;
        return
            feeReduction >= INITIAL_FEE
                ? uint24(INITIAL_FEE / 2)
                : uint24(INITIAL_FEE - feeReduction);
    }

    // --- Token Order Check ---
    function _isPookaToken0(
        PoolKey calldata poolKey
    ) internal view returns (bool) {
        return Currency.unwrap(poolKey.currency0) == address(POOKA);
    }

    // --- Position Tracking ---
    function _updatePosition(address user, bool isAdd) internal {
        console.log("Updating position for user: %s", user);
        uint256 pookaAmount = POOKA.balanceOf(user);

        for (uint i = 0; i < userPositions[user].length; i++) {
            Position storage pos = userPositions[user][i];
            pos.pookaAmount = pookaAmount;
        }

        if (isAdd && pookaAmount > 0) {
            userPositions[user].push(
                Position({pookaAmount: POOKA.balanceOf(user)})
            );
        }
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
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // --- Swap Handling ---
    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    )
        internal
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Remove view modifier and add onlyPoolManager

        address user = abi.decode(hookData, (address));
        if (user == address(0)) revert InvalidSwap();

        // State modification - must remove view
        if (address(POOKA) == Currency.unwrap(key.currency0)) {
            if (params.zeroForOne) {
                totalPookaSwapped += uint256(-params.amountSpecified);
            }
        } else if (address(POOKA) == Currency.unwrap(key.currency1)) {
            if (!params.zeroForOne) {
                totalPookaSwapped += uint256(-params.amountSpecified);
            }
        }

        if (user == owner()) {
            console.log("Owner swap detected");
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        console.log("User swap detected");
        uint24 feeAmount = getUserFee(user);
        console.log("Fee amount: %d", feeAmount);
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeAmount // Return dynamic fee
        );
    }

    // update the position of the user's POOKA holdings
    // so that its available at the time of the next swap
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        console.log("After swap");

        // make sure pooka is one of the tokens in the swap
        if (
            Currency.unwrap(key.currency0) != _getPookaAddress() &&
            Currency.unwrap(key.currency1) != _getPookaAddress()
        ) {
            return (this.afterSwap.selector, 0);
        }

        address user = abi.decode(hookData, (address));
        if (user == address(0)) revert InvalidSwap();

        console.log("After swap for user: %s", user);
        console.log("POOKA balance: %d", POOKA.balanceOf(user));

        if (POOKA.balanceOf(user) > 0) {
            _updatePosition(user, true);
        }

        return (this.afterSwap.selector, 0);
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

    // function _handleOwnerSwap(
    //     PoolKey calldata /*key*/,
    //     IPoolManager.SwapParams calldata /*params*/
    // ) internal pure returns (bytes4, BeforeSwapDelta, uint24) {
    //     // Owner swaps bypass fees and price limits
    //     return (
    //         BaseHook.beforeSwap.selector,
    //         BeforeSwapDeltaLibrary.ZERO_DELTA,
    //         0 // 0% swap fee
    //     );
    // }
}
