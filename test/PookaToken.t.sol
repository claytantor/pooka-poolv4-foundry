// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Test} from "forge-std/Test.sol";
import {PookaToken} from "../src/PookaToken.sol"; // Ensure correct import path

/// @title TestPookaToken
/// @notice Test for a simple ERC-20 token for Pooka compatible with our Uniswap V4 hooks and pool examples.
contract TestPookaToken is Test, Deployers {
    PookaToken public Pooka;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M Pooka tokens

    function setUp() public {
        owner = address(this); // The test contract itself acts as the deployer/owner
        user1 = vm.addr(1); // Create a new address for user1
        user2 = vm.addr(2); // Create a new address for user2

        // make the pool address the owner
        vm.prank(owner);

        // Deploy the PookaToken contract
        Pooka = new PookaToken(INITIAL_SUPPLY);
    }

    /// @notice Test if token name and symbol are correct
    function testTokenMetadata() public view {
        assertEq(Pooka.name(), "Pooka Token");
        assertEq(Pooka.symbol(), "POOKA");
        assertEq(Pooka.decimals(), 18);
    }

    /// @notice Test if the total supply is correctly initialized
    function testTotalSupply() public view {
        assertEq(Pooka.totalSupply(), INITIAL_SUPPLY);
    }

    /// @notice Test that the owner receives the initial supply
    function testOwnerBalance() public view {
        assertEq(Pooka.balanceOf(owner), INITIAL_SUPPLY);
    }

    /// @notice Test transferring tokens between users
    function testTransfer() public {
        uint256 transferAmount = 10_000 * 10 ** 18;

        // Owner transfers 10,000 Pooka to user1
        Pooka.transfer(user1, transferAmount);

        // Check balances
        assertEq(Pooka.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
        assertEq(Pooka.balanceOf(user1), transferAmount);
    }

    /// @notice Test allowance and transferFrom
    function testApprovalAndTransferFrom() public {
        uint256 approveAmount = 5_000 * 10 ** 18;
        uint256 transferAmount = 3_000 * 10 ** 18;

        // Owner approves user1 to spend 5,000 Pooka
        Pooka.approve(user1, approveAmount);

        // Check allowance
        assertEq(Pooka.allowance(owner, user1), approveAmount);

        // Perform the transferFrom via user1
        vm.prank(user1); // Simulate user1 calling
        Pooka.transferFrom(owner, user1, transferAmount);

        // Check balances
        assertEq(Pooka.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
        assertEq(Pooka.balanceOf(user1), transferAmount);

        // Check remaining allowance
        assertEq(Pooka.allowance(owner, user1), approveAmount - transferAmount);
    }

    /// @notice Test minting new Pooka tokens
    function testMinting() public {
        uint256 mintAmount = 500_000 * 10 ** 18; // Mint 500k more Pooka

        // Owner mints additional Pooka to user1
        Pooka.mint(user1, mintAmount);

        // Check new balances and total supply
        assertEq(Pooka.balanceOf(user1), mintAmount);
        assertEq(Pooka.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    // test burn
    function testBurning() public {
        uint256 burnAmount = 100_000 * 10 ** 18;

        // Owner burns 100,000 Pooka
        Pooka.burn(burnAmount);

        // Check new balances and total supply
        assertEq(Pooka.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(Pooka.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    /// @notice Test that a non-owner cannot mint tokens
    function testMintingByNonOwnerFails() public {
        uint256 mintAmount = 100_000 * 10 ** 18;

        // User1 tries to mint (should fail)
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        Pooka.mint(user1, mintAmount);
    }
}
