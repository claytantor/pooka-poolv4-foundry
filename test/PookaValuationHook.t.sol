// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {PookaToken} from "../src/PookaToken.sol";
import {PookaValuationHook} from "../src/PookaValuationHook.sol";

import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

/// @title TestPookaValuationHook
/// @notice Test for the valuation hook contract for Pooka compatible with our Uniswap V4 hooks and pool examples.
contract TestPookaValuationHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    Currency token0Currency;
    Currency token1Currency;

    PoolManager public poolManager;
    IPoolManager public ipoolManager;
    PoolSwapTest public poolSwapTest;
    MockERC20 public mockDAI;
    PookaToken public pookaToken;
    PookaValuationHook public pookaValuationHook;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M Pooka tokens

    /// @dev Converts a uint256 to its ASCII string decimal representation.
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /// @dev Pads the fractional string with leading zeros so it has exactly `decimals` digits.
    function padFractional(
        string memory fractional,
        uint256 decimals
    ) internal pure returns (string memory) {
        bytes memory fracBytes = bytes(fractional);
        uint256 missingZeros = decimals > fracBytes.length
            ? decimals - fracBytes.length
            : 0;
        bytes memory zeros = new bytes(missingZeros);
        for (uint256 i = 0; i < missingZeros; i++) {
            zeros[i] = "0";
        }
        return string(abi.encodePacked(zeros, fractional));
    }

    uint256 internal constant Q96 = 2 ** 96;
    // 1.0001 in Q64.96 fixed-point format.
    // In Q64.96, 1.0001 is approximately 1.0001 * 2^96.
    uint256 internal constant ONE_POINT_0001_Q96 = 7922816251426433759; // ~1.0001 in Q64.96
    // An approximation for sqrt(1.0001) in Q64.96. For better precision use a refined value.
    uint256 internal constant SQRT_1_0001_Q96 = 792283; // rough approximation in Q64.96

    function setUp() public {
        // Step 1 + 2
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        owner = address(this); // The test contract itself acts as the deployer/owner
        user1 = vm.addr(1); // Create a new address for user1
        user2 = vm.addr(2); // Create a new address for user2

        // make the pool address the owner
        vm.prank(owner);

        // Deploy the PookaToken contract
        pookaToken = new PookaToken(INITIAL_SUPPLY);
        // Mint a bunch of POOKA to ourselves and to address(1)
        pookaToken.mint(owner, 100_000 ether);
        pookaToken.mint(user1, 1000 ether);

        // Set the token0 and token1 currencies
        mockDAI = new MockERC20("Mock DAI Token", "DAI", 18);
        // Mint a bunch of TOKEN to ourselves and to address(1)
        mockDAI.mint(owner, 100_000 ether);
        mockDAI.mint(user1, 100 ether);

        // With this (sort tokens by address):
        if (address(mockDAI) < address(pookaToken)) {
            token0Currency = Currency.wrap(address(mockDAI));
            token1Currency = Currency.wrap(address(pookaToken));
        } else {
            token0Currency = Currency.wrap(address(pookaToken));
            token1Currency = Currency.wrap(address(mockDAI));
        }

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        deployCodeTo(
            "PookaValuationHook.sol",
            abi.encode(manager, address(mockDAI), address(pookaToken)),
            address(flags)
        );
        pookaValuationHook = PookaValuationHook(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        mockDAI.approve(address(swapRouter), type(uint256).max);
        mockDAI.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Approve our POOKA for spending on the swap router and modify liquidity router
        pookaToken.approve(address(swapRouter), type(uint256).max);
        pookaToken.approve(address(modifyLiquidityRouter), type(uint256).max);

        require(
            address(pookaValuationHook) != address(0),
            "pookaValuationHook not deployed!"
        );

        // Initialize the DAI POOKA pool
        (key, ) = initPool(
            token0Currency, // Currency 0 = POOKA
            token1Currency, // Currency 1 = DAI
            pookaValuationHook, // Hook Contract
            3000, // Swap Fees
            Constants.SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        // Add initial liquidity to the pool
        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 200 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // Some liquidity from -600 to +600 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // Add this check for currency order
        require(
            key.currency1 == Currency.wrap(address(mockDAI)) &&
                key.currency0 == Currency.wrap(address(pookaToken)),
            "Token order mismatch"
        );
    }

    function test_addLiquidity() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(owner);

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-10);

        // Add liquidity of 10 DAI
        uint256 daiToAdd = 10 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            Constants.SQRT_PRICE_1_1,
            daiToAdd
        );

        // owner Add liquidity
        modifyLiquidityRouter.modifyLiquidity{value: daiToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            hookData
        );
    }

    // a test that makes sure that the owner can swap without fees
    function test_ownerSwapPooka2Dai() public {
        // Set user address in hook data
        // bytes memory hookData = abi.encode(owner);
        vm.startPrank(owner);

        uint256 initialPooka = pookaToken.balanceOf(owner);
        uint256 initialDai = mockDAI.balanceOf(owner);

        // Add this check before swapping
        require(
            key.currency1 == Currency.wrap(address(mockDAI)) &&
                key.currency0 == Currency.wrap(address(pookaToken)),
            "Token order mismatch"
        );

        // Set test settings
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        // Pass the owner's address in hook data so that the hook recognizes the owner.
        bytes memory hookData = abi.encode(owner);

        // Instead of using TickMath.MIN_SQRT_PRICE + 1,
        // use a moderate tick offset relative to a known reference (e.g., tick 0).
        // For token0 -> token1 swap (price decreasing), a lower tick (e.g. -100) is used.
        uint160 sqrtPriceLimitX96_10 = TickMath.getSqrtPriceAtTick(-10); // Tick -10 should have liquidity

        // Swap 1 POOKA for DAI
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.1 ether, // Exact input: 0.1 POOKA
            sqrtPriceLimitX96: sqrtPriceLimitX96_10 // Allow price to increase
        });

        swapRouter.swap(key, params, testSettings, hookData);

        // // calculate the the difference in balances
        uint256 diffPooka = initialPooka - pookaToken.balanceOf(owner);
        console.log("Diff (POOKA)", diffPooka);

        uint256 balDai = mockDAI.balanceOf(owner);
        console.log("Owner Balance (DAI)", balDai);

        assertEq(
            pookaToken.balanceOf(owner),
            initialPooka - 0.1 ether,
            "Owner should pay no fees"
        );

        // Verify DAI received
        assertGt(mockDAI.balanceOf(owner), initialDai, "Should receive DAI");

        vm.stopPrank();
    }

    function test_userSwapPooka2Dai_chargesFees() public {
        // Assume user1 starts with a sufficient POOKA balance.
        // If needed, mint POOKA to user1. (This line is illustrative; adapt it to your setup.)
        uint256 initialUser1Balance = 1 ether;
        pookaToken.mint(user1, initialUser1Balance);

        // Set hook data to encode the non-owner user (user1)
        bytes memory hookData = abi.encode(user1);

        // Verify token ordering is correct
        require(
            key.currency1 == Currency.wrap(address(mockDAI)) &&
                key.currency0 == Currency.wrap(address(pookaToken)),
            "Token order mismatch"
        );

        // Configure test settings (same as for the owner test)
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        // Get user1's initial balances
        uint256 pookaBalanceBefore = pookaToken.balanceOf(user1);
        uint256 daiBalanceBefore = mockDAI.balanceOf(user1);

        // Add this check for currency order
        require(
            key.currency1 == Currency.wrap(address(mockDAI)) &&
                key.currency0 == Currency.wrap(address(pookaToken)),
            "Token order mismatch"
        );

        // Set up swap parameters for POOKA → DAI:
        // zeroForOne: true means swapping token0 (POOKA) to token1 (DAI)
        // amountSpecified: -0.05 POOKA (exact input swap)
        // sqrtPriceLimitX96: a price limit that allows the swap to execute (price decreasing)
        uint256 swapAmount = 0.5 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Before the swap, user1 must approve the swapRouter to spend their POOKA tokens.
        vm.prank(user1);
        pookaToken.approve(address(swapRouter), type(uint256).max);

        // Simulate the swap being initiated by user1
        vm.prank(user1);
        swapRouter.swap(key, params, testSettings, hookData);

        // Post-swap balances
        uint256 pookaBalanceAfter = pookaToken.balanceOf(user1);
        uint256 daiBalanceAfter = mockDAI.balanceOf(user1);

        // Calculate expected 0.3% fee
        // 5 * 10e17
        uint256 expectedDiff = 5 * 10e16; // amount after deduction
        uint256 actualDiff = pookaBalanceBefore - pookaBalanceAfter;
        assertEq(actualDiff, expectedDiff, "Incorrect balance");

        assertLt(
            pookaBalanceAfter,
            pookaBalanceBefore,
            "POOKA balance should decrease"
        );

        console.log("POOKA balance before", pookaBalanceBefore);
        console.log("POOKA balance after", pookaBalanceAfter);
        console.log("DAI balance before", daiBalanceBefore);
        console.log("DAI balance after", daiBalanceAfter);
        console.log("Expected Diff", expectedDiff);

        // Verify DAI received
        assertGt(daiBalanceAfter, daiBalanceBefore, "No DAI received in swap");
    }

    function test_userSwapDai2Pooka_chargesFees() public {
        // Assume user1 starts with a sufficient POOKA balance.
        // If needed, mint POOKA to user1. (This line is illustrative; adapt it to your setup.)
        uint256 initialUser1Balance = 151 ether;
        mockDAI.mint(user1, initialUser1Balance);

        // Set hook data to encode the non-owner user (user1)
        bytes memory hookData = abi.encode(user1);

        // Verify token ordering is correct
        require(
            key.currency1 == Currency.wrap(address(mockDAI)) &&
                key.currency0 == Currency.wrap(address(pookaToken)),
            "Token order mismatch"
        );

        // Configure test settings (same as for the owner test)
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        // Get user1's initial balances
        uint256 pookaBalanceBefore = pookaToken.balanceOf(user1);
        uint256 daiBalanceBefore = mockDAI.balanceOf(user1);

        // calculate the the fee for the user
        uint256 feeBefore = pookaValuationHook.getUserFee(user1);

        console.log("Fee before", feeBefore);
        console.log("POOKA balance before", pookaBalanceBefore);
        console.log("DAI balance before", daiBalanceBefore);

        // Set up swap parameters for POOKA → DAI:
        // zeroForOne: true means swapping token0 (POOKA) to token1 (DAI)
        // amountSpecified: -0.05 POOKA (exact input swap)
        // sqrtPriceLimitX96: a price limit that allows the swap to execute (price decreasing)
        uint256 swapAmount = 151.5 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        // Before the swap, user1 must approve the swapRouter to spend their POOKA tokens.
        vm.prank(user1);
        mockDAI.approve(address(swapRouter), type(uint256).max);

        // Simulate the swap being initiated by user1
        vm.prank(user1);
        swapRouter.swap(key, params, testSettings, hookData);

        // Get user1's initial balances
        uint256 pookaBalanceAfter = pookaToken.balanceOf(user1);
        uint256 daiBalanceAfter = mockDAI.balanceOf(user1);
        // calculate the the fee for the user
        uint256 feeAfter = pookaValuationHook.getUserFee(user1);

        console.log("Fee after", feeAfter);
        console.log("POOKA balance after", pookaBalanceAfter);
        console.log("DAI balance after", daiBalanceAfter);

        //assert that fee before is greater than fee after
        assertGt(feeBefore, feeAfter, "Fee should be greater before swap");
    }
}
