// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IExecutableProposal.sol";

contract Proposal {
    // Declare variables
    uint public proposalId;
    string public title;
    string public description;
    uint public budget;
    address public recipient; // Address of the contract implementing IExecutableProposal
    bool public executed;
    address public creator;

    // Mapping to track vote amounts for each participant
    mapping(address => uint) public votes;

    event ProposalExecuted(uint proposalId, uint amount, address recipient);
    event ProposalCanceled(uint proposalId);

    // Constructor to initialize the proposal with required details
    constructor(uint _proposalId, string memory _title, string memory _description, uint _budget, address _recipient) {
        proposalId = _proposalId;
        title = _title;
        description = _description;
        budget = _budget;
        recipient = _recipient;
        creator = msg.sender;
        executed = false;
    }

    // Function to execute the proposal
    function executeProposal(uint numVotes, uint numTokens) external payable {
        require(!executed, "Proposal already executed");
        require(msg.sender == creator, "Only the proposal creator can execute");
        require(numVotes > 0, "No votes to execute");

        // Check if the proposal has met its threshold (you could include a logic for that)
        // For simplicity, let's assume the proposal is ready to execute when the condition is met
        executed = true;

        // Send the budget to the recipient (external contract)
        IExecutableProposal(recipient).executeProposal(proposalId, numVotes, numTokens);

        // Emit an event for transparency
        emit ProposalExecuted(proposalId, numTokens, recipient);
    }

    // Function to cancel the proposal
    function cancelProposal() external {
        require(msg.sender == creator, "Only the creator can cancel the proposal");
        require(!executed, "Proposal already executed");
        
        // Logic to refund any staked tokens (simplified for this example)
        emit ProposalCanceled(proposalId);
    }

    // Function to add votes to this proposal
    function addVotes(address participant, uint voteAmount) external {
        require(!executed, "Cannot vote on executed proposal");
        votes[participant] += voteAmount;
    }

    // Function to refund tokens to participants (after proposal cancelation)
    function refundVotes(address participant, uint voteAmount) external {
        require(msg.sender == creator, "Only creator can refund");
        require(votes[participant] >= voteAmount, "Insufficient votes to refund");

        votes[participant] -= voteAmount;
        // Refund logic here
    }
}
