// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IExecutableProposal.sol";

import "./votingToken.sol";

contract QuadraticVoting {
    address public owner;
    uint256 public tokenPrice;
    uint256 public maxTokens;
    uint256 public votingBudget;
    bool public isVotingOpen;

    VotingToken public token;

    uint256 public proposalCount;
    uint256[] public proposalIds; // Track proposal IDs

    enum ProposalStatus {
        Pending,
        Approved,
        Cancelled,
        Executed,
        Dismissed
    }

    struct Proposal {
        string title;
        string description;
        uint256 budget;
        address creator;
        IExecutableProposal recipient;
        ProposalStatus status;
        bool isSignaling;
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

    modifier votingOpen() {
        require(isVotingOpen, "Voting is not open");
        _;
    }

    constructor(uint256 _tokenPrice, uint256 _maxTokens) {
        require(_tokenPrice > 0, "Invalid token price");
        require(_maxTokens > 0, "Invalid token cap");

        owner = msg.sender;
        tokenPrice = _tokenPrice;
        maxTokens = _maxTokens;
        token = new VotingToken(0);
    }

    function openVoting() external payable onlyOwner {
        require(!isVotingOpen, "Voting already open");
        isVotingOpen = true;
        votingBudget = msg.value;
    }

    function addParticipant() external payable {
        require(
            msg.value >= tokenPrice,
            "Insufficient Ether to buy at least 1 token"
        );
        require(!participants[msg.sender], "Already registered");

        uint256 tokensToMint = msg.value / tokenPrice;
        require(
            token.totalSupply() + tokensToMint <= maxTokens,
            "Token cap exceeded"
        );

        participants[msg.sender] = true;
        token.mint(msg.sender, tokensToMint);
    }

    function removeParticipant() external {
        require(participants[msg.sender], "Not a participant");
        participants[msg.sender] = false;
    }

    function buyTokens() external payable onlyParticipant {
        require(msg.value >= tokenPrice, "Not enough Ether");
        uint256 tokensToMint = msg.value / tokenPrice;
        require(
            token.totalSupply() + tokensToMint <= maxTokens,
            "Token cap exceeded"
        );

        token.mint(msg.sender, tokensToMint);
    }

    function sellTokens(uint256 amount) external onlyParticipant {
        require(token.balanceOf(msg.sender) >= amount, "Insufficient tokens");

        uint256 refund = amount * tokenPrice;

        // Effects first
        token.burn(msg.sender, amount);

        // Interaction last
        (bool sent, ) = payable(msg.sender).call{value: refund}("");
        require(sent, "Refund transfer failed");
    }

    function addProposal(
        string memory title,
        string memory description,
        uint256 budget,
        address proposalAddress
    ) external onlyParticipant votingOpen returns (uint256) {
        proposalCount++;
        Proposal storage p = proposals[proposalCount];
        p.title = title;
        p.description = description;
        p.budget = budget;
        p.creator = msg.sender;
        p.recipient = IExecutableProposal(proposalAddress);
        p.status = ProposalStatus.Pending;
        p.isSignaling = (budget == 0);
        p.exists = true;

        proposalIds.push(proposalCount); // Track proposal ID

        return proposalCount;
    }

    function cancelProposal(uint256 id) external votingOpen {
        Proposal storage p = proposals[id];
        require(p.exists, "Invalid proposal");
        require(p.creator == msg.sender, "Not creator");
        require(p.status == ProposalStatus.Pending, "Cannot cancel");

        for (uint256 i = 0; i < p.voters.length; i++) {
            address voter = p.voters[i];
            uint256 votes = p.votes[voter];
            if (votes > 0) {
                //uint256 tokensToRefund = votes * votes;

                // Burn tokens (no transfer back, tokens stay in the contract)
                token.burn(voter, votes); // Burn equivalent tokens used for voting

                p.votes[voter] = 0;
            }
        }

        p.status = ProposalStatus.Cancelled;
    }

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

        // Calculate the tokens to burn for the new votes
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

        // Effects: Update vote count and total votes
        p.votes[msg.sender] = totalVotes;
        p.totalVotes += newVotes;

        // If it's the first vote, track the voter
        if (prevVotes == 0) {
            p.voters.push(msg.sender);
        }

        // Check and possibly execute the proposal
        _checkAndExecuteProposal(proposalId);
    }

    function _checkAndExecuteProposal(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        if (p.isSignaling || p.status != ProposalStatus.Pending) {
            return;
        }

        if (p.totalVotes >= 50 && address(this).balance >= p.budget) {
            // Mark as approved (initially)
            p.status = ProposalStatus.Approved;

            // Burn tokens and clear vote mappings
            for (uint256 i = 0; i < p.voters.length; i++) {
                address voter = p.voters[i];
                p.votes[voter] = 0; // burn tokens (they stay in contract)
            }

            uint256 numVotes = p.totalVotes;
            uint256 numTokens = numVotes * numVotes;

            (bool success, ) = address(p.recipient).call{
                value: p.budget,
                gas: 100_000
            }(
                abi.encodeWithSelector(
                    IExecutableProposal.executeProposal.selector,
                    proposalId,
                    numVotes,
                    numTokens
                )
            );

            require(success, "Proposal execution failed");

            // Update budget and status only if call succeeded
            votingBudget -= p.budget;
            p.status = ProposalStatus.Executed;
        }
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

        require(token.transfer(msg.sender, refund), "Token refund failed");

        // If the user's votes reach zero, remove them from the voters list
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

    function closeVoting() external onlyOwner votingOpen {
        isVotingOpen = false;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];

            if (p.status != ProposalStatus.Pending) continue;

            if (p.budget == 0) {
                // Signaling proposal — execute with no Ether
                p.status = ProposalStatus.Executed;

                uint256 numVotes = p.totalVotes; // Total votes cast for this proposal
                uint256 numTokens = numVotes * numVotes; // Total tokens used for votes (quadratic voting)

                try
                    IExecutableProposal(p.recipient).executeProposal{
                        gas: 100_000
                    }(proposalIds[i], numVotes, numTokens)
                {} catch {}
            } else {
                // Funding proposal not approved — refund voters
                for (uint256 j = 0; j < p.voters.length; j++) {
                    address voter = p.voters[j];
                    uint256 votes = p.votes[voter];
                    if (votes > 0) {
                        uint256 refund = votes * votes; // Refund the tokens used for voting
                        require(token.transfer(voter, refund), "Refund failed");
                        p.votes[voter] = 0;
                    }
                }
                p.status = ProposalStatus.Dismissed;
            }
        }

        // Return remaining unspent Ether to owner
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
}
