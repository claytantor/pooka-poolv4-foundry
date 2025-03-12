// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {EasyPosm} from "../src/EasyPosm.sol";

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
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AddLiquidityScript is Script {
    using CurrencyLibrary for Currency;
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    // --- pool configuration --- //
    // fees paid by swappers that accrue to liquidity providers
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;

    // --- liquidity position configuration --- //
    uint256 public token0Amount = 1e18;
    uint256 public token1Amount = 1e18;

    // range of the position
    // int24 tickLower = -600; // must be a multiple of tickSpacing
    // int24 tickUpper = 600;
    int24 tickLower = TickMath.minUsableTick(tickSpacing);
    int24 tickUpper = TickMath.maxUsableTick(tickSpacing);
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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load private key from .env

        address dai = vm.envAddress("DAI_ADDRESS");
        address pooka = vm.envAddress("POOKA_ADDRESS");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address hookContractAddress = vm.envAddress("POOKA_HOOK_ADDRESS");
        address lpRouterAddress = vm.envAddress(
            "MODIFY_LIQUIDITY_ROUTER_ADDRESS"
        );
        address swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");

        IHooks hookContract = IHooks(hookContractAddress);
        poolManager = IPoolManager(poolManagerAddress);

        address positionManagerAddress = vm.envAddress(
            "POSITION_MANAGER_ADDRESS"
        );

        posm = PositionManager(payable(positionManagerAddress));
        // make the liquidity position router
        lpRouter = new PoolModifyLiquidityTest(poolManager);
        swapRouter = new PoolSwapTest(poolManager);

        address permitAddress = vm.envAddress("PERMIT2_ADDRESS");

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

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions

        // approve the tokens to the routers
        ERC20 token0 = ERC20(token0Address);
        ERC20 token1 = ERC20(token1Address);

        token0.approve(lpRouterAddress, type(uint256).max);
        token1.approve(lpRouterAddress, type(uint256).max);
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

        // get the pool from the Pool manager
        // Construct the PoolKey
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0Address), // Convert token address to Currency type
            currency1: Currency.wrap(token1Address),
            fee: lpFee,
            tickSpacing: 60, // Example tick spacing (depends on fee tier)
            hooks: hookContract // Convert the hook address
        });

        // provisions full-range liquidity twice. Two different periphery contracts used for example purposes.
        IPoolManager.ModifyLiquidityParams memory liqParams = IPoolManager
            .ModifyLiquidityParams(tickLower, tickUpper, 1000 ether, 0);
        lpRouter.modifyLiquidity(poolKey, liqParams, "");

        posm.mint(
            poolKey,
            tickLower,
            tickUpper,
            100e18,
            10_000e18,
            10_000e18,
            msg.sender,
            block.timestamp + 300,
            ""
        );

        // swap some tokens
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne
                ? TickMath.MIN_SQRT_PRICE + 1
                : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
        });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(poolKey, params, testSettings, "");

        vm.stopBroadcast();
    }

    // function tokenApprovals(
    //     address token0,
    //     address token1,
    //     address permitAddress
    // ) public {
    //     Currency currency0 = Currency.wrap(token0);
    //     Currency currency1 = Currency.wrap(token1);
    //     if (!currency0.isAddressZero()) {
    //         // Inline ERC20 and permitManager calls
    //         ERC20(token0).approve(permitAddress, type(uint256).max);
    //         IAllowanceTransfer(permitAddress).approve(
    //             token0, // token0 is already an address
    //             address(posm),
    //             type(uint160).max,
    //             type(uint48).max
    //         );
    //     }
    //     if (!currency1.isAddressZero()) {
    //         ERC20(token1).approve(permitAddress, type(uint256).max);
    //         IAllowanceTransfer(permitAddress).approve(
    //             token1,
    //             address(posm),
    //             type(uint160).max,
    //             type(uint48).max
    //         );
    //     }
    // }
}
