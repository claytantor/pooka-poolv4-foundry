// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// import {EasyPosm} from "../../src/EasyPosm.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {PositionManager} from "v4-periphery/PositionManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
// import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityProvider} from "../../src/LiquidityProvider.sol";
import {TickGetter} from "../../src/TickGetter.sol";
import {UniversalRouter} from "universal-router/contracts/UniversalRouter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IV4Router} from "v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {Commands} from "universal-router/contracts/libraries/Commands.sol";

contract SwapPookaUniversalRouter is Script {
    // struct CallbackData {
    //     uint256 amountEach;
    //     Currency currency0;
    //     Currency currency1;
    //     address sender;
    // }

    // using CurrencyLibrary for Currency;
    // using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    UniversalRouter public router;
    IPoolManager public poolManager;
    IPermit2 public permit2;

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

    uint256 constant V4_SWAP = 0x10;

    // range of the position
    int24 tickLower = TickMath.minUsableTick(tickSpacing);
    int24 tickUpper = TickMath.maxUsableTick(tickSpacing);
    /////////////////////////////////////

    function setUp() public {}

    // function approvePosmCurrency(
    //     IPositionManager _posm,
    //     Currency currency,
    //     address permit2Address
    // ) internal {
    //     permit2 = IAllowanceTransfer(address(permit2Address));
    //     // Because POSM uses permit2, we must execute 2 permits/approvals.
    //     // 1. First, the caller must approve permit2 on the token.
    //     ERC20(Currency.unwrap(currency)).approve(
    //         permit2Address,
    //         type(uint256).max
    //     );
    //     // 2. Then, the caller must approve POSM as a spender of permit2
    //     permit2.approve(
    //         Currency.unwrap(currency),
    //         address(_posm),
    //         type(uint160).max,
    //         type(uint48).max
    //     );
    // }

    // function calculateAmounts(
    //     int24 currentTick,
    //     int24 tickLowerAmount,
    //     int24 tickUpperAmount,
    //     uint128 liquidity
    // ) public pure returns (uint256 amount0, uint256 amount1) {
    //     // Get current sqrt price directly from tick
    //     uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(currentTick);

    //     // Get boundary sqrt prices using tick->sqrtPrice conversion
    //     uint160 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(
    //         tickLowerAmount
    //     );
    //     uint160 sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(
    //         tickUpperAmount
    //     );

    //     // uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1
    //     uint128 amount0L = LiquidityAmounts.getLiquidityForAmount0(
    //         sqrtPriceX96,
    //         sqrtPriceLowerX96,
    //         liquidity
    //     );

    //     uint128 amount1L = LiquidityAmounts.getLiquidityForAmount1(
    //         sqrtPriceX96,
    //         sqrtPriceUpperX96,
    //         liquidity
    //     );

    //     return (amount0L, amount1L);
    // }

    function approveTokenWithPermit2(
        address token,
        uint160 amount,
        uint48 expiration
    ) external {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(token, address(router), amount, expiration);
    }

    function swapExactInputSingle(
        PoolKey memory key,
        uint128 amountIn,
        uint128 minAmountOut,
        bytes memory hookData
    ) internal returns (uint256 amountOut) {
        // Encode the Universal Router command

        bytes memory commands = abi.encodePacked(uint8(V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        // struct ExactInputSingleParams {
        //     PoolKey poolKey;
        //     bool zeroForOne;
        //     uint128 amountIn;
        //     uint128 amountOutMinimum;
        //     bytes hookData;
        // }

        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: hookData
            })
        );
        params[1] = abi.encode(key.currency0, amountIn);
        params[2] = abi.encode(key.currency1, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 deadline = block.timestamp + 600;
        router.execute(commands, inputs, deadline);

        // Verify and return the output amount
        // amountOut = IERC20(address(key.currency1)).balanceOf(address(this));
        amountOut = CurrencyLibrary.balanceOf(key.currency1, address(this));
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
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

        address universalRouterAddress = vm.envAddress(
            "UNIVERSAL_ROUTER_ADDRESS"
        );
        address payable payableURAddress = payable(universalRouterAddress);
        router = UniversalRouter(payableURAddress);

        // position manager
        address permit2Address = vm.envAddress("PERMIT2_ADDRESS");
        permit2 = IPermit2(permit2Address);

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

        // get the current balance of the tokens
        uint256 token0Balance = token0.balanceOf(vm.addr(deployerPrivateKey));
        uint256 token1Balance = token1.balanceOf(vm.addr(deployerPrivateKey));
        console.log("Token0 balance: ", token0Balance, token0Address);
        console.log("Token1 balance: ", token1Balance, token1Address);

        // Pass the owner's address in hook data so that the hook recognizes the owner.
        bytes memory hookData = abi.encode(vm.addr(deployerPrivateKey));

        uint256 amountOut = swapExactInputSingle(poolKey, 1e18, 1e18, hookData);

        console.log("Amount out Swapped: ", amountOut);

        // // swap some tokens
        // bool zeroForOne = true;
        // int256 amountSpecified = 1.01 ether;
        // IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
        //     zeroForOne: zeroForOne,
        //     amountSpecified: amountSpecified,
        //     sqrtPriceLimitX96: zeroForOne
        //         ? TickMath.MIN_SQRT_PRICE + 1
        //         : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
        // });
        // PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
        //     .TestSettings({takeClaims: false, settleUsingBurn: false});
        // swapRouter.swap(poolKey, params, testSettings, hookData);

        vm.stopBroadcast();
    }
}
