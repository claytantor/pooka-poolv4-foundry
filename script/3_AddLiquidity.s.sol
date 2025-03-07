// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

contract AddLiquidityScript is Script {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // --- pool configuration --- //
    // fees paid by swappers that accrue to liquidity providers
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;

    // --- liquidity position configuration --- //
    uint256 public token0Amount = 1e18;
    uint256 public token1Amount = 1e18;

    // range of the position
    int24 tickLower = -600; // must be a multiple of tickSpacing
    int24 tickUpper = 600;
    /////////////////////////////////////

    function setUp() public {}

    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load private key from .env

        address dai = vm.envAddress("DAI_ADDRESS");
        address pooka = vm.envAddress("POOKA_ADDRESS");
        address create2DeployerAddress = vm.envAddress(
            "CREATE2_DEPLOYER_ADDRESS"
        );
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address hookContractAddress = vm.envAddress("POOKA_HOOK_CONTRACT");
        IHooks hookContract = IHooks(hookContractAddress);

        Currency currency0;
        Currency currency1;

        // With this (sort tokens by address):
        if (dai < pooka) {
            currency0 = Currency.wrap(dai);
            currency1 = Currency.wrap(pooka);
        } else {
            currency0 = Currency.wrap(pooka);
            currency1 = Currency.wrap(dai);
        }

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });
    }
}
