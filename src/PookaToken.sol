// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PookaToken
/// @notice A simple ERC-20 token for Pooka compatible with our Uniswap V4 hooks and pool examples.
contract PookaToken is ERC20, Ownable {
    address public immutable hook;

    constructor(
        uint256 initialSupply
    )
        ERC20("Pooka Token", "POOKA")
        Ownable(msg.sender) // Pass msg.sender as the initial owner.
    {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Mint additional tokens.
     * @dev Only the contract owner can mint new tokens.
     * @param to The address receiving the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Transfer tokens.
     * @dev Only the hook contract can transfer tokens.
     * @param from The address from which to transfer tokens.
     * @param to The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function transfer(address from, address to, uint256 amount) external {
        _transfer(from, to, amount);
    }

    /**
     * @notice Approve tokens.
     * @dev Only the hook contract can approve tokens.
     * @param owner The address owning the tokens.
     * @param spender The address allowed to spend the tokens.
     * @param amount The amount of tokens to approve.
     */
    function approve(address owner, address spender, uint256 amount) external {
        _approve(owner, spender, amount);
    }

    /** total suppy */
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    /** burn */
    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }
}
