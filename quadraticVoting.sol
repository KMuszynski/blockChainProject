// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./IExecutableProposal.sol";

import "./votingToken.sol";

contract QuadraticVoting is ReentrancyGuard {
    address public owner;
    uint256 public tokenPrice;
    uint256 public maxTokens;
    uint256 public votingBudget;
    bool public isVotingOpen;
    uint256 public participantCount;
    mapping(address => uint256) public lockedTokens;

    VotingToken public token;

    uint256 public proposalCount;
    uint256[] public proposalIds;

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
        require(msg.value > 0, "Initial funding required");
        votingBudget = msg.value;
        isVotingOpen = true;
    }

    function getParticipantCount() public view returns (uint256) {
        return participantCount;
    }

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

        
        if (excess > 0) {
            (bool refunded, ) = msg.sender.call{value: excess}("");
            require(refunded, "Refund failed");
        }
    }

    function removeParticipant() external nonReentrant {
        require(participants[msg.sender], "Not a participant");

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

    function sellTokens(uint256 amount) external onlyParticipant nonReentrant {
        require(amount > 0, "Cannot sell zero tokens");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient tokens");

        uint256 refund = amount * tokenPrice;

        token.burn(msg.sender, amount);

        (bool sent, ) = payable(msg.sender).call{value: refund}("");
        require(sent, "Refund transfer failed");
    }

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

    function cancelProposal(uint256 id) external votingOpen {
        Proposal storage p = proposals[id];

        require(p.exists, "Invalid proposal");
        require(p.creator == msg.sender, "Only creator can cancel");
        require(p.status == ProposalStatus.Pending, "Cannot cancel finalized");


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

    function _checkAndExecuteProposal(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        if (p.isSignaling || p.status != ProposalStatus.Pending) {
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
            numPendingFunds;

        if (p.totalVotes < threshold || totalBudget < p.budget) {
            return;
        }

        p.status = ProposalStatus.Approved;

        uint256 numVotes = p.totalVotes;
        uint256 numTokens = numVotes * numVotes;

        for (uint256 i = 0; i < p.voters.length; i++) {
            address voter = p.voters[i];
            uint256 voted = p.votes[voter];
            if (voted == 0) continue;

            uint256 usedTokens = voted * voted;
            lockedTokens[voter] -= usedTokens;
            p.votes[voter] = 0;
        }

        votingBudget += (numTokens * tokenPrice);

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

        votingBudget -= p.budget;
        p.status = ProposalStatus.Executed;
    }

    function closeVoting() external onlyOwner votingOpen {
        isVotingOpen = false;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage p = proposals[proposalIds[i]];

            if (p.status != ProposalStatus.Pending) continue;

            if (p.budget == 0) {
                p.status = ProposalStatus.Executed;

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
                        p.votes[voter] = 0;
                        lockedTokens[voter] -= refund;
                    }
                }
            } else {
                for (uint256 j = 0; j < p.voters.length; j++) {
                    address voter = p.voters[j];
                    uint256 votes = p.votes[voter];
                    if (votes > 0) {
                        uint256 refund = votes * votes;
                        require(token.transfer(voter, refund), "Refund failed");
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
