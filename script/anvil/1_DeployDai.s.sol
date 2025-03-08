// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
// import {DaiToken} from "../src/DaiToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DAI is ERC20 {
    // Deployer gets 1M tokens (18 decimals) on deployment
    constructor() ERC20("DAI", "DAI") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}

contract DeployDAI is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load from environment variable

        vm.startBroadcast(deployerPrivateKey); // Specify the sender
        DAI token = new DAI(); // Deploy and auto-mint
        vm.stopBroadcast(); // Stop broadcasting

        // Log the token address and supply
        console.log("DAI Token deployed to: ", address(token));
        console.log(
            "Deployer balance: ",
            token.balanceOf(vm.addr(deployerPrivateKey)) / 1e18,
            "DAI"
        );
    }
}
