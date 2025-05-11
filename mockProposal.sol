// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../IExecutableProposal.sol";  // Ensure the interface path is correct

// Mock implementation of IExecutableProposal
contract MockProposal is IExecutableProposal {
    uint256 public lastId;
    uint256 public lastVotes;
    uint256 public lastTokens;

    // `executeProposal` accepts parameters in the interface, but here we won't pass them when called in the test.
    // The parameters are just stored internally instead.
    function executeProposal(uint256 proposalId, uint256 totalVotes, uint256 totalTokens) external override payable {
        lastId = proposalId;
        lastVotes = totalVotes;
        lastTokens = totalTokens;
    }
}
