// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

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
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Load private key from .env

        // Sepolia Addresses (Replace with actual addresses)
        // Load all addresses from environment variables
        address dai = vm.envAddress("DAI_ADDRESS");
        address pooka = vm.envAddress("POOKA_ADDRESS");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");

        // Mine a salt that will produce a hook address with the correct flags
        IPoolManager poolManager = IPoolManager(poolManagerAddress);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory hookCreationCode = abi.encodePacked(
            type(PookaValuationHook).creationCode,
            abi.encode(address(poolManager), dai, pooka)
        );
        (address hookAddress, bytes32 salt) = mineHookAddress(
            hookCreationCode,
            flags
        );

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions

        PookaValuationHook pvh = deployHook(
            hookCreationCode,
            salt,
            hookAddress
        );

        require(
            address(pvh) == hookAddress,
            "DeployPookaHook: hook address mismatch"
        );

        console.log("POOKA_HOOK_ADDRESS=", address(pvh));

        vm.stopBroadcast();
    }

    function isValidHookAddress(
        address hookAddress,
        uint160 targetFlags
    ) internal pure returns (bool) {
        uint160 addr = uint160(hookAddress);
        return
            addr != 0 && (addr & uint160(Hooks.ALL_HOOK_MASK)) == targetFlags;
    }

    function mineHookAddress(
        bytes memory creationCode,
        uint160 targetFlags
    ) internal view returns (address, bytes32) {
        bytes32 initCodeHash = keccak256(creationCode);
        for (uint256 i = 0; i < 100000; i++) {
            bytes32 salt = keccak256(abi.encodePacked(msg.sender, i));
            address predictedAddress = vm.computeCreate2Address(
                salt,
                initCodeHash
            );
            if (isValidHookAddress(predictedAddress, targetFlags)) {
                return (predictedAddress, salt);
            }
        }
        revert("Failed to mine a valid hook address within 100k attempts");
    }

    function deployHook(
        bytes memory creationCode,
        bytes32 salt,
        address expectedAddress
    ) internal returns (PookaValuationHook) {
        address deployedAddress;
        assembly {
            let codeSize := mload(creationCode)
            let codeStart := add(creationCode, 0x20)
            deployedAddress := create2(0, codeStart, codeSize, salt)
        }
        require(deployedAddress == expectedAddress, "CREATE2 address mismatch");
        require(deployedAddress != address(0), "CREATE2 deployment failed");
        return PookaValuationHook(deployedAddress);
    }
}
