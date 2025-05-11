// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./IExecutableProposal.sol";

import "./votingToken.sol";

contract QuadraticVoting is ReentrancyGuard {
    address public owner;
    uint256 public tokenPrice; // Price of one token in wei
    uint256 public maxTokens; // Max number of tokens that can ever exist
    uint256 public votingBudget; // Total ether available for funding proposals
    bool public isVotingOpen;
    uint256 public participantCount;
    mapping(address => uint256) public lockedTokens; // Tracks tokens currently staked in votes

    VotingToken public token;

    uint256 public proposalCount;
    uint256[] public proposalIds;

    //enum to represent the proposal status
    enum ProposalStatus {
        Pending,
        Approved,
        Cancelled,
        Executed,
        Dismissed
    }

    //struct defining a proposal
    struct Proposal {
        string title;
        string description;
        uint256 budget;
        address creator;
        IExecutableProposal recipient;
        ProposalStatus status;
        bool isSignaling; // True if budget == 0 (signaling proposal)
        uint256 totalVotes;
        mapping(address => uint256) votes;
        address[] voters;
        bool exists;
    }

    mapping(address => bool) public participants;
    mapping(uint256 => Proposal) private proposals;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlyParticipant() {
        require(participants[msg.sender], "Not a participant");
        _;
    }

    modifier votingOpen() { // Ensure voting session is currently open
        require(isVotingOpen, "Voting is not open");
        _;
    }

    // Constructor initializes contract settings
    constructor(uint256 _tokenPrice, uint256 _maxTokens) {
        require(_tokenPrice > 0, "Invalid token price");
        require(_maxTokens > 0, "Invalid token cap");

        owner = msg.sender;
        tokenPrice = _tokenPrice;
        maxTokens = _maxTokens;
        token = new VotingToken(0);
    }

    event VotingOpened(uint256 initialBudget);

    // Opens the voting session and sets the initial budget
    function openVoting() external payable onlyOwner {
        require(!isVotingOpen, "Voting already open");
        require(msg.value > 0, "Initial funding required");
        votingBudget = msg.value;
        isVotingOpen = true;
        emit VotingOpened(msg.value);
    }

    // Returns the number of participants
    function getParticipantCount() public view returns (uint256) {
        return participantCount;
    }

    // Internal function to count proposals awaiting funding
    function _countPendingFunding() internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.status == ProposalStatus.Pending && p.budget > 0) {
                count++;
            }
        }
        return count;
    }

    // Register new participant and mint tokens
    function addParticipant() external payable {
        require(
            msg.value >= tokenPrice,
            "Insufficient Ether to buy at least 1 token"
        );

        require(!participants[msg.sender], "Already registered");

        uint256 tokensToMint = msg.value / tokenPrice;
        uint256 excess = msg.value % tokenPrice;

        require(
            token.totalSupply() + tokensToMint <= maxTokens,
            "Token cap exceeded"
        );

        participants[msg.sender] = true;
        token.mint(msg.sender, tokensToMint);
        participantCount++;

        // Refund any excess ETH
        if (excess > 0) {
            (bool refunded, ) = msg.sender.call{value: excess}("");
            require(refunded, "Refund failed");
        }
    }

    // Allows a participant to deregister and get their ETH back
    function removeParticipant() external nonReentrant {
        require(participants[msg.sender], "Not a participant");
        require(lockedTokens[msg.sender] == 0, "Must withdraw all votes first");
        

        participants[msg.sender] = false;
        participantCount--;

        uint256 userBalance = token.balanceOf(msg.sender);

        if (userBalance > 0) {
            token.burn(msg.sender, userBalance);

            
            uint256 refund = userBalance * tokenPrice;
            (bool sent, ) = payable(msg.sender).call{value: refund}("");
            require(sent, "Refund failed");
        }
    }

    // Allows participants to buy more tokens
    function buyTokens() external payable onlyParticipant {
        require(msg.value >= tokenPrice, "Not enough Ether");

        uint256 tokensToMint = msg.value / tokenPrice;
        require(tokensToMint > 0, "Insufficient Ether for 1 token");
        require(
            token.totalSupply() + tokensToMint <= maxTokens,
            "Token cap exceeded"
        );

        token.mint(msg.sender, tokensToMint);

        
        uint256 excess = msg.value % tokenPrice;
        if (excess > 0) {
            (bool sent, ) = payable(msg.sender).call{value: excess}("");
            require(sent, "Refund failed");
        }
    }

    // Allows participants to sell their unlocked tokens
    function sellTokens(uint256 amount) external onlyParticipant nonReentrant {
        require(amount > 0, "Cannot sell zero tokens");

        uint256 freeBalance = token.balanceOf(msg.sender) - lockedTokens[msg.sender];
        require(freeBalance >= amount, "Cannot sell locked tokens");

        uint256 refund = amount * tokenPrice;

        token.burn(msg.sender, amount);

        (bool sent, ) = payable(msg.sender).call{value: refund}("");
        require(sent, "Refund transfer failed");
    }

     // Create a new proposal
    function addProposal(
        string memory title,
        string memory description,
        uint256 budget,
        address proposalAddress
    ) external onlyParticipant votingOpen returns (uint256) {
        require(proposalAddress.code.length > 0, "Invalid contract address");

        proposalCount++;
        uint256 id = proposalCount;


        Proposal storage p = proposals[id];
        p.title = title;
        p.description = description;
        p.budget = budget;
        p.creator = msg.sender;
        p.recipient = IExecutableProposal(proposalAddress);
        p.status = ProposalStatus.Pending;
        p.isSignaling = (budget == 0);
        p.exists = true;

        proposalIds.push(id);

        return id;
    }

    // Cancel a proposal and refund all votes
    function cancelProposal(uint256 id) external votingOpen {
        Proposal storage p = proposals[id];

        require(p.exists, "Invalid proposal");
        require(p.creator == msg.sender, "Only creator can cancel");
        require(p.status == ProposalStatus.Pending, "Cannot cancel finalized");

        // Refund all staked tokens
        for (uint256 i = 0; i < p.voters.length; i++) {
            address voter = p.voters[i];
            uint256 votes = p.votes[voter];
            if (votes > 0) {

                uint256 refund = votes * votes;


                require(token.transfer(voter, refund), "Token refund failed");
                lockedTokens[voter] -= refund;

                p.votes[voter] = 0;
            }
        }

        delete p.voters;
        p.status = ProposalStatus.Cancelled;
    }

    // Stake quadratic votes on a proposal
    function stake(uint256 proposalId, uint256 newVotes)
        external
        votingOpen
        onlyParticipant
    {
        Proposal storage p = proposals[proposalId];
    

        require(p.exists, "Invalid proposal");
        require(p.status == ProposalStatus.Pending, "Proposal not active");
        require(newVotes > 0, "Must vote at least once");

        uint256 prevVotes = p.votes[msg.sender];
        uint256 totalVotes = prevVotes + newVotes;

        uint256 tokensRequired = totalVotes *
            totalVotes -
            prevVotes *
            prevVotes;

        require(
            token.allowance(msg.sender, address(this)) >= tokensRequired,
            "Insufficient allowance"
        );
        require(
            token.transferFrom(msg.sender, address(this), tokensRequired),
            "Token transfer failed"
        );


        lockedTokens[msg.sender] += tokensRequired;


        p.votes[msg.sender] = totalVotes;
        p.totalVotes += newVotes;


        if (prevVotes == 0) {
            p.voters.push(msg.sender);
        }

        _checkAndExecuteProposal(proposalId);
    }

    // Internal logic to autoexecute funding proposals
    function _checkAndExecuteProposal(uint256 proposalId) internal nonReentrant {
        Proposal storage p = proposals[proposalId];
        if (p.budget == 0 || p.status != ProposalStatus.Pending) {
            return;
        }


        uint256 totalBudget = votingBudget;
        uint256 numParticipants = participantCount;
        uint256 numPendingFunds = _countPendingFunding();

        uint256 weightBase = 2e17; // 0.2 * 1e18
        uint256 frac = (p.budget * 1e18) / totalBudget;
        uint256 thresholdFP = weightBase + frac;
        uint256 threshold = (thresholdFP * numParticipants) /
            1e18 +
            numPendingFunds; // Dynamic threshold with formula from the task

        if (p.totalVotes < threshold || totalBudget < p.budget) {
            return;
        }

        p.status = ProposalStatus.Approved;

        uint256 numVotes = p.totalVotes;

        uint256 tokensConsumed = 0;
        
        // Burn all votes
        for (uint256 i = 0; i < p.voters.length; i++) {
            address voter = p.voters[i];
            uint256 vcount = p.votes[voter];
            if (vcount == 0) continue;

            uint256 cost = vcount * vcount;
            tokensConsumed += cost;

            // Unlock and zero out
            lockedTokens[voter] -= cost;
            p.votes[voter] = 0;
        }

        token.burn(address(this), tokensConsumed);

        votingBudget += tokensConsumed * tokenPrice;

        (bool success, ) = address(p.recipient).call{ value: p.budget, gas:100_000 }(
        abi.encodeWithSelector(
            IExecutableProposal.executeProposal.selector,
            proposalId,
            numVotes,
            tokensConsumed
        )
        );
        require(success, "Proposal execution failed");

        votingBudget -= p.budget;
        p.status = ProposalStatus.Executed;
    }

    // Ends voting, finalizes or dismisses proposals, refunds tokens, and transfers remaining ETH to owner
    function closeVoting() external onlyOwner votingOpen {
        isVotingOpen = false;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];

            if (p.status != ProposalStatus.Pending) continue;

            if (p.budget == 0) {
                p.status = ProposalStatus.Executed;  // Signaling proposal: execute

                uint256 numVotes = p.totalVotes;
                uint256 numTokens = numVotes * numVotes;

                try
                    IExecutableProposal(p.recipient).executeProposal{
                        gas: 100_000
                    }(proposalIds[i], numVotes, numTokens)
                {} catch {}

                for (uint256 j = 0; j < p.voters.length; j++) {
                    address voter = p.voters[j];
                    uint256 votes = p.votes[voter];
                    if (votes > 0) {
                        uint256 refund = votes * votes;
                        require(token.transfer(voter, refund), "Refund failed");
                        lockedTokens[voter] -= refund;
                        p.votes[voter] = 0;
                    }
                }
            } else {
                // Funding proposal: dismiss and refund
                for (uint256 j = 0; j < p.voters.length; j++) {
                    address voter = p.voters[j];
                    uint256 votes = p.votes[voter];
                    if (votes > 0) {
                        uint256 refund = votes * votes;
                        require(token.transfer(voter, refund), "Refund failed");
                        lockedTokens[voter] -= refund;
                        p.votes[voter] = 0;
                    }
                }
                p.status = ProposalStatus.Dismissed;


            }
        }

        uint256 remainingBalance = address(this).balance;
        (bool sent, ) = owner.call{value: remainingBalance}("");
        require(sent, "Budget refund failed");
    }

    function getERC20() external view returns (VotingToken) {
        return token;
    }

    function getPendingProposals()
        external
        view
        votingOpen
        returns (uint256[] memory)
    {
        uint256 count = 0;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.budget > 0 && p.status == ProposalStatus.Pending) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.budget > 0 && p.status == ProposalStatus.Pending) {
                result[j++] = proposalIds[i];
            }
        }

        return result;
    }

    function getApprovedProposals()
        external
        view
        votingOpen
        returns (uint256[] memory)
    {
        uint256 count = 0;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.budget > 0 && p.status == ProposalStatus.Approved) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.budget > 0 && p.status == ProposalStatus.Approved) {
                result[j++] = proposalIds[i];
            }
        }

        return result;
    }

    function getSignalingProposals()
        external
        view
        votingOpen
        returns (uint256[] memory)
    {
        uint256 count = 0;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.budget == 0 && p.status == ProposalStatus.Pending) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];
            if (p.budget == 0 && p.status == ProposalStatus.Pending) {
                result[j++] = proposalIds[i];
            }
        }

        return result;
    }

    function getProposalInfo(uint256 proposalId)
        external
        view
        returns (
            string memory title,
            string memory description,
            uint256 budget,
            address creator,
            ProposalStatus status,
            bool isSignaling,
            uint256 totalVotes
        )
    {
        Proposal storage p = proposals[proposalId];
        require(p.exists, "Invalid proposal");

        return (
            p.title,
            p.description,
            p.budget,
            p.creator,
            p.status,
            p.isSignaling,
            p.totalVotes
        );
    }

    function withdrawFromProposal(uint256 proposalId, uint256 votesToRemove)
        external
        votingOpen
        onlyParticipant
    {
        Proposal storage p = proposals[proposalId];
        require(p.exists, "Invalid proposal");
        require(
            p.status == ProposalStatus.Pending,
            "Cannot withdraw from finalized proposal"
        );

        uint256 prevVotes = p.votes[msg.sender];
        require(
            prevVotes >= votesToRemove && votesToRemove > 0,
            "Invalid vote withdrawal"
        );

        uint256 newVotes = prevVotes - votesToRemove;
        uint256 refund = prevVotes * prevVotes - newVotes * newVotes;

        p.votes[msg.sender] = newVotes;
        p.totalVotes -= votesToRemove;

        lockedTokens[msg.sender] -= refund;

        require(token.transfer(msg.sender, refund), "Token refund failed");

        if (newVotes == 0) {
            for (uint256 i = 0; i < p.voters.length; i++) {
                if (p.voters[i] == msg.sender) {
                    p.voters[i] = p.voters[p.voters.length - 1];
                    p.voters.pop();
                    break;
                }
            }
        }
    }

    receive() external payable {
        revert("Send ether through defined functions");
    }
}
