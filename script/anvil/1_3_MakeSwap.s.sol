// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// // import {EasyPosm} from "../../src/EasyPosm.sol";
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
// // import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityProvider} from "../../src/LiquidityProvider.sol";
import {TickGetter} from "../../src/TickGetter.sol";
import {UniversalRouter} from "universal-router/contracts/UniversalRouter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IV4Router} from "v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {Commands} from "universal-router/contracts/libraries/Commands.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MakeSwap is Script {
    using StateLibrary for IPoolManager;

    UniversalRouter public router;
    IPoolManager public poolManager;
    IPermit2 public permit2;
    IHooks public hookContract;

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

    function makePoolDaiPookaKey(
        address daiAddress,
        address pookaAddress
    ) internal view returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        // address token0Address;
        // address token1Address;

        // With this (sort tokens by address):
        if (daiAddress < pookaAddress) {
            currency0 = Currency.wrap(daiAddress);
            // token0Address = daiAddress;
            currency1 = Currency.wrap(pookaAddress);
            // token1Address = pookaAddress;
            console.log("Dai is token0 and Pooka is token1");
        } else {
            currency0 = Currency.wrap(pookaAddress);
            // token0Address = pookaAddress;
            currency1 = Currency.wrap(daiAddress);
            // token1Address = daiAddress;
            console.log("Pooka is token0 and Dai is token1");
        }

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        return poolKey;
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
        amountOut = CurrencyLibrary.balanceOf(key.currency1, address(this));
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load from environment variable

        // the swap tokens
        address daiAddress = vm.envAddress("DAI_ADDRESS");
        ERC20 daiToken = ERC20(daiAddress);
        console.log("DAI Token deployed to: ", daiAddress);
        // get the balance of the token
        console.log(
            "Token balance: ",
            daiToken.balanceOf(vm.addr(deployerPrivateKey)) / 1e18,
            "DAI"
        );

        address pookaAddress = vm.envAddress("POOKA_ADDRESS");
        ERC20 pookaToken = ERC20(pookaAddress);
        console.log("POOKA Token deployed to: ", pookaAddress);
        // get the balance of the token
        console.log(
            "Token balance: ",
            pookaToken.balanceOf(vm.addr(deployerPrivateKey)) / 1e18,
            "POOKA"
        );

        // now the infrastructure
        // pool manager
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        poolManager = IPoolManager(poolManagerAddress);

        // hook contract
        address hookContractAddress = vm.envAddress("POOKA_HOOK_ADDRESS");
        hookContract = IHooks(hookContractAddress);

        address universalRouterAddress = vm.envAddress(
            "UNIVERSAL_ROUTER_ADDRESS"
        );
        address payable payableURAddress = payable(universalRouterAddress);
        router = UniversalRouter(payableURAddress);

        address permit2Address = vm.envAddress("PERMIT2_ADDRESS");
        permit2 = IPermit2(permit2Address);

        // now make the pool key
        PoolKey memory poolKey = makePoolDaiPookaKey(daiAddress, pookaAddress);

        // unwap the pool key tokens
        address token0Address = Currency.unwrap(poolKey.currency0);
        console.log("token 0 address: ", token0Address);
        IERC20 token0 = IERC20(token0Address);

        address token1Address = Currency.unwrap(poolKey.currency1);
        console.log("token 1 address: ", token1Address);
        IERC20 token1 = IERC20(token1Address);

        // start the vm broadcast
        vm.startBroadcast(deployerPrivateKey);

        // approve the tokens to the router
        token0.approve(universalRouterAddress, token0Amount);
        token1.approve(universalRouterAddress, token1Amount);

        // make the swap
        bytes memory hookData = abi.encode(pookaAddress);
        uint256 amountOut = swapExactInputSingle(poolKey, 1 ether, 0, hookData);
        console.log("Amount out Swapped: ", amountOut);

        // end the vm broadcast
        vm.stopBroadcast();
    }
}
