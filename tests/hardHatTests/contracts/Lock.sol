// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Lock {
    uint256 public unlockTime;
    address public owner;

    event Withdrawal(uint256 amount, uint256 when);

    constructor(uint256 _unlockTime) payable {
        require(_unlockTime > block.timestamp, "Unlock time should be in the future");
        unlockTime = _unlockTime;
        owner = msg.sender;
    }

    function withdraw() public {
        require(block.timestamp >= unlockTime, "You can't withdraw yet");
        require(msg.sender == owner, "You aren't the owner");

        emit Withdrawal(address(this).balance, block.timestamp);
        payable(owner).transfer(address(this).balance);
    }
}
