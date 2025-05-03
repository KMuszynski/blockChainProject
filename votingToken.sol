// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VotingToken is ERC20 {
    // Constructor to set the token name, symbol, and initial supply
    constructor(uint256 initialSupply) ERC20("VotingToken", "VOTE") {
        _mint(msg.sender, initialSupply); // Mint the initial supply to the contract deployer
    }

    // Mint function to create new tokens (equivalent to your custom mint)
    function mint(address to, uint256 amount) external {
        _mint(to, amount); // Mint tokens to the specified address
    }

    // Burn function to remove tokens from a specific address
    function burn(address from, uint256 amount) external {
        _burn(from, amount); // Burn tokens from the specified address
    }

    // Override transfer function to add custom logic if needed (like additional events)
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount); 
        // Custom logic if needed, or you can emit additional events here
        return success;
    }

    // Override approve function to add custom logic if needed (like additional events)
    function approve(address spender, uint256 amount) public override returns (bool) {
        bool success = super.approve(spender, amount);
        // Custom logic if needed, or you can emit additional events here
        return success;
    }

    // Override transferFrom function to add custom logic if needed (like additional events)
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        // Custom logic if needed, or you can emit additional events here
        return success;
    }
}
