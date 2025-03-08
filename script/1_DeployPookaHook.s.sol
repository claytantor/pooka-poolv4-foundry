// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {PookaValuationHook} from "../src/PookaValuationHook.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";

/// @title DeployPookaHook
/// @notice creates a DAI/POOKA pool and deploys the PookaValuationHook contract to the Sepolia testnet.
contract DeployPookaHook is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load private key from .env

        // Sepolia Addresses (Replace with actual addresses)
        // Load all addresses from environment variables
        address dai = vm.envAddress("DAI_ADDRESS");
        address pooka = vm.envAddress("POOKA_ADDRESS");
        address create2DeployerAddress = vm.envAddress(
            "CREATE2_DEPLOYER_ADDRESS"
        );
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            create2DeployerAddress,
            flags,
            type(PookaValuationHook).creationCode,
            constructorArgs
        );

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions

        PookaValuationHook pvh = new PookaValuationHook{salt: salt}(
            IPoolManager(poolManager),
            dai,
            pooka
        );

        require(
            address(pvh) == hookAddress,
            "DeployPookaHook: hook address mismatch"
        );

        vm.stopBroadcast();
    }
}
