// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IExecutableProposal.sol";

contract Proposal is IExecutableProposal {
    uint256 public proposalId;
    string public title;
    string public description;
    uint256 public budget;
    bool public executed;

    constructor(
        uint256 _proposalId,
        string memory _title,
        string memory _description,
        uint256 _budget
    ) {
        proposalId = _proposalId;
        title = _title;
        description = _description;
        budget = _budget;
        executed = false;
    }

    function executeProposal(
        uint256 _proposalId,
        uint256 numVotes,
        uint256 numTokens
    ) external payable override {
        require(!executed && _proposalId == proposalId);
        executed = true;
        emit Executed(_proposalId, numVotes, numTokens, msg.value);
    }

    event Executed(uint256 proposalId, uint256 numVotes, uint256 numTokens, uint256 valueReceived);
}