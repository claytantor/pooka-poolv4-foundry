// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GetDaiValue is Script {
    function run() external view {
        uint256 deployerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY"); // Load from environment variable

        address daiAddress = vm.envAddress("DAI_ADDRESS");

        ERC20 dai = ERC20(daiAddress);

        console.log("DAI Token deployed to: ", address(dai));

        // get the balance of the token
        console.log(
            "Token balance: ",
            dai.balanceOf(vm.addr(deployerPrivateKey)) / 1e18,
            "DAI"
        );
    }
}
