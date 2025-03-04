// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {PookaToken} from "../src/PookaToken.sol";

/// @title DeployPooka
/// @notice Deploys the Pooka ERC20 token to the Sepolia testnet.
contract DeployPooka is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load private key from .env

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions

        // Deploy the Pooka token with an initial supply of 1M tokens (with 18 decimals)
        PookaToken Pooka = new PookaToken(1_000_000 * 10 ** 18);

        vm.stopBroadcast();

        console.log("Pooka Token deployed to:", address(Pooka));
    }
}
