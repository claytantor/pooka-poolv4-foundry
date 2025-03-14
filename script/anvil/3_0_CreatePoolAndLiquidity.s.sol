// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {EasyPosm} from "../../src/EasyPosm.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {PositionManager} from "v4-periphery/PositionManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityProvider} from "../../src/LiquidityProvider.sol";
import {TickGetter} from "../../src/TickGetter.sol";

contract CreatePoolAndLiquidity is Script {
    struct CallbackData {
        uint256 amountEach;
        Currency currency0;
        Currency currency1;
        address sender;
    }

    using CurrencyLibrary for Currency;
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    /////////////////////////////////////
    // --- Parameters to Configure --- //
    /////////////////////////////////////

    // --- pool configuration --- //
    // fees paid by swappers that accrue to liquidity providers
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;

    // starting price of the pool, in sqrtPriceX96
    uint160 startingPrice = 79228162514264337593543950336; // floor(sqrt(1) * 2^96)

    // --- liquidity position configuration --- //
    uint256 public token0Amount = 1e18;
    uint256 public token1Amount = 1e18;

    // range of the position
    // int24 tickLower = TickMath.minUsableTick(tickSpacing);
    // int24 tickUpper = TickMath.maxUsableTick(tickSpacing);
    int24 tickLower = -600;
    int24 tickUpper = 600;
    /////////////////////////////////////

    IPoolManager poolManager;
    IPositionManager posm;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapRouter;

    function setUp() public {}

    function approvePosmCurrency(
        IPositionManager _posm,
        Currency currency,
        address permit2Address
    ) internal {
        IAllowanceTransfer permit2 = IAllowanceTransfer(
            address(permit2Address)
        );
        // Because POSM uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        ERC20(Currency.unwrap(currency)).approve(
            permit2Address,
            type(uint256).max
        );
        // 2. Then, the caller must approve POSM as a spender of permit2
        permit2.approve(
            Currency.unwrap(currency),
            address(_posm),
            type(uint160).max,
            type(uint48).max
        );
    }

    function calculateAmounts(
        int24 currentTick,
        int24 tickLowerAmount,
        int24 tickUpperAmount,
        uint128 liquidity
    ) public pure returns (uint256 amount0, uint256 amount1) {
        // Get current sqrt price directly from tick
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(currentTick);

        // Get boundary sqrt prices using tick->sqrtPrice conversion
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(
            tickLowerAmount
        );
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(
            tickUpperAmount
        );

        // uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1
        uint128 amount0L = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceX96,
            sqrtPriceLowerX96,
            liquidity
        );

        uint128 amount1L = LiquidityAmounts.getLiquidityForAmount1(
            sqrtPriceX96,
            sqrtPriceUpperX96,
            liquidity
        );

        return (amount0L, amount1L);
    }

    // // Helper function to calculate expected deposits
    // function calculateExpectedDeposits(
    //     PoolKey memory key,
    //     int24 tickLowerVal,
    //     int24 tickUpperVal,
    //     int256 liquidityDelta
    // ) internal view returns (uint256 amount0, uint256 amount1) {
    //     // Implementation depends on your math library
    //     // Example using TickMath:

    //     // (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(key);
    //     (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
    //         sqrtPriceX96,
    //         TickMath.getSqrtRatioAtTick(tickLowerVal),
    //         TickMath.getSqrtRatioAtTick(tickUpperVal),
    //         uint128(liquidityDelta)
    //     );
    // }

    function safeInitializePool(
        IPoolManager pms,
        PoolKey memory poolKey,
        uint160 startingPriceTick0
    ) internal {
        // Convert PoolKey to PoolId
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        // Get current pool state
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(pms, poolId);

        // Only initialize if pool hasn't been created yet
        if (sqrtPriceX96 == 0) {
            poolManager.initialize(poolKey, startingPriceTick0);
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load private key from .env

        address dai = vm.envAddress("DAI_ADDRESS");
        address pooka = vm.envAddress("POOKA_ADDRESS");

        // pool manager
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        poolManager = IPoolManager(poolManagerAddress);

        // hook contract
        address hookContractAddress = vm.envAddress("POOKA_HOOK_ADDRESS");
        IHooks hookContract = IHooks(hookContractAddress);

        address lpRouterAddress = vm.envAddress(
            "MODIFY_LIQUIDITY_ROUTER_ADDRESS"
        );
        address swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");

        // position manager
        address positionManagerAddress = vm.envAddress(
            "POSITION_MANAGER_ADDRESS"
        );
        posm = PositionManager(payable(positionManagerAddress));

        // make the liquidity position router
        lpRouter = new PoolModifyLiquidityTest(poolManager);
        console.log("MODIFY_LIQUIDITY_ROUTER_ADDRESS=", address(lpRouter));

        swapRouter = new PoolSwapTest(poolManager);
        console.log("SWAP_ROUTER_ADDRESS=", address(swapRouter));

        address permitAddress = vm.envAddress("PERMIT2_ADDRESS");

        // Deploy helper
        LiquidityProvider liquidityProvider = new LiquidityProvider(
            poolManager
        );

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

        // approve the tokens to the routers
        ERC20 token0 = ERC20(token0Address);
        ERC20 token1 = ERC20(token1Address);

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions

        // create the pool
        // poolManager.initialize(poolKey, startingPrice);
        // Safely initialize if needed
        uint160 startingPriceT0 = TickMath.getSqrtPriceAtTick(0); // Initialize at tick 0
        safeInitializePool(poolManager, poolKey, startingPriceT0);

        token0.approve(lpRouterAddress, 0);
        token0.approve(lpRouterAddress, 1000 ether);
        token1.approve(lpRouterAddress, 0);
        token1.approve(lpRouterAddress, 1000 ether);
        token0.approve(poolManagerAddress, 0);
        token0.approve(poolManagerAddress, type(uint256).max);
        token1.approve(poolManagerAddress, 0);
        token1.approve(poolManagerAddress, type(uint256).max);

        uint256 allowance0 = token0.allowance(
            vm.addr(deployerPrivateKey),
            lpRouterAddress
        );
        uint256 allowance1 = token1.allowance(
            vm.addr(deployerPrivateKey),
            lpRouterAddress
        );
        console.log("Token0 allowance lprouter:", allowance0);
        console.log("Token1 allowance: lprouter", allowance1);

        // Log allowances for debugging
        uint256 allowance0Pool = token0.allowance(
            vm.addr(deployerPrivateKey),
            poolManagerAddress
        );
        uint256 allowance1Pool = token1.allowance(
            vm.addr(deployerPrivateKey),
            poolManagerAddress
        );
        console.log("Token0 allowance to PoolManager:", allowance0Pool);
        console.log("Token1 allowance to PoolManager:", allowance1Pool);

        token0.approve(swapRouterAddress, type(uint256).max);
        token1.approve(swapRouterAddress, type(uint256).max);
        approvePosmCurrency(
            posm,
            Currency.wrap(address(token0Address)),
            permitAddress
        );
        approvePosmCurrency(
            posm,
            Currency.wrap(address(token1Address)),
            permitAddress
        );

        // get the current balance of the tokens
        uint256 token0Balance = token0.balanceOf(vm.addr(deployerPrivateKey));
        uint256 token1Balance = token1.balanceOf(vm.addr(deployerPrivateKey));
        console.log("Signer Token0 balance: ", token0Balance, token0Address);
        console.log("Signer Token1 balance: ", token1Balance, token1Address);

        // CANT GET THIS TO WORK
        // // provisions full-range liquidity
        // IPoolManager.ModifyLiquidityParams memory liqParams = IPoolManager
        //     .ModifyLiquidityParams(tickLower, tickUpper, 100 ether, 0);
        // lpRouter.modifyLiquidity(poolKey, liqParams, "");

        // 1. Prepare liquidity parameters
        // int24 tickLower = -600;
        // int24 tickUpper = 600;
        // int256 liquidityDelta = int256(1000 ether);
        // bytes32 positionId = keccak256(
        //     abi.encode(address(liquidityProvider), tickLower, tickUpper)
        // );

        // 2. Get initial state
        // (uint128 initialLiquidity, , , ) = poolManager.positions(positionId);
        uint256 initialBalance0 = IERC20(Currency.unwrap(poolKey.currency0))
            .balanceOf(address(poolManager));
        uint256 initialBalance1 = IERC20(Currency.unwrap(poolKey.currency1))
            .balanceOf(address(poolManager));

        console.log("poolManager Token0 balance before: ", initialBalance0);
        console.log("poolManager Token1 balance before: ", initialBalance1);

        (, int24 currentTick, , ) = StateLibrary.getSlot0(
            poolManager,
            poolKey.toId()
        );

        // Calculate required amounts based on position
        (uint256 amount0, uint256 amount1) = calculateAmounts(
            currentTick,
            tickLower,
            tickUpper,
            100 ether // liquidityDelta
        );

        // Execute liquidity modification
        liquidityProvider.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(1000 ether),
                salt: bytes32(0)
            }),
            amount0,
            amount1
        );

        vm.stopBroadcast();

        uint256 finalBalance0 = IERC20(Currency.unwrap(poolKey.currency0))
            .balanceOf(address(poolManager));
        uint256 finalBalance1 = IERC20(Currency.unwrap(poolKey.currency1))
            .balanceOf(address(poolManager));

        console.log("poolManager Token0 balance after: ", finalBalance0);
        console.log("poolManager Token1 balance after: ", finalBalance1);

        // // Assert liquidity increased
        // assertEq(
        //     uint256(int256(newLiquidity)),
        //     uint256(int256(initialLiquidity)) + uint256(liquidityDelta),
        //     "Liquidity not added"
        // );

        // // Assert token balances changed
        // assertGt(finalBalance0, initialBalance0, "Token0 not deposited");
        // assertGt(finalBalance1, initialBalance1, "Token1 not deposited");

        // Verify returned amounts match expectations
        // (uint256 expected0, uint256 expected1) = calculateExpectedDeposits(
        //     poolKey,
        //     tickLower,
        //     tickUpper,
        //     liquidityDelta
        // );

        // (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(
        //     poolManager,
        //     poolKey
        // );

        // (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
        //     sqrtPriceX96,
        //     TickMath.getSqrtRatioAtTick(tickLowerVal),
        //     TickMath.getSqrtRatioAtTick(tickUpperVal),
        //     uint128(liquidityDelta)
        // );

        // assertApproxEqRel(
        //     amount0,
        //     expected0,
        //     0.01e18,
        //     "Token0 amount mismatch"
        // ); // 1% tolerance
        // assertApproxEqRel(
        //     amount1,
        //     expected1,
        //     0.01e18,
        //     "Token1 amount mismatch"
        // );
    }
}
