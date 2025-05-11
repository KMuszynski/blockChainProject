const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("QuadraticVoting Contract", function () {
  let votingToken, quadraticVoting;
  let owner, participant, otherAccount;
  let tokenPrice, maxTokens;

  beforeEach(async function () {
    [owner, participant, otherAccount] = await ethers.getSigners();

    // Deploy VotingToken and wait
    const Token = await ethers.getContractFactory("VotingToken");
    votingToken = await Token.deploy(0);
    await votingToken.waitForDeployment();
    console.log("VotingToken deployed at:", votingToken.target);

    tokenPrice = ethers.parseEther("0.1");
    maxTokens = 1_000_000;

    // Deploy QuadraticVoting and wait
    const QV = await ethers.getContractFactory("QuadraticVoting");
    quadraticVoting = await QV.deploy(tokenPrice, maxTokens);
    await quadraticVoting.waitForDeployment();
    console.log("QuadraticVoting deployed at:", quadraticVoting.target);

    // Now both addresses should be defined
    expect(quadraticVoting.target).to.not.be.undefined;
    expect(quadraticVoting.target).to.not.equal(
      "0x0000000000000000000000000000000000000000"
    );
  });

  it("should deploy the VotingToken contract", async function () {
    expect(await votingToken.totalSupply()).to.equal(0);
  });

  it("should deploy the QuadraticVoting contract", async function () {
    expect(await quadraticVoting.tokenPrice()).to.equal(tokenPrice);
    expect(await quadraticVoting.maxTokens()).to.equal(maxTokens);
  });

  describe("openVoting", function () {
    it("should allow the owner to open voting", async function () {
      const initialBalance = await ethers.provider.getBalance(
        quadraticVoting.target
      );
      const oneEth = ethers.parseEther("1");

      await expect(quadraticVoting.connect(owner).openVoting({ value: oneEth }))
        .to.emit(quadraticVoting, "VotingOpened")
        .withArgs(oneEth);

      expect(await quadraticVoting.isVotingOpen()).to.be.true;
      expect(await quadraticVoting.votingBudget()).to.equal(oneEth);

      // use bigint addition
      const after = await ethers.provider.getBalance(quadraticVoting.target);
      expect(after).to.equal(initialBalance + oneEth);
    });

    it("should revert if a non-owner tries to open voting", async function () {
      await expect(
        quadraticVoting
          .connect(participant)
          .openVoting({ value: ethers.parseEther("1") })
      ).to.be.revertedWith("Not the owner");
    });

    it("should revert if no ether is sent", async function () {
      await expect(
        quadraticVoting.connect(owner).openVoting({ value: 0 })
      ).to.be.revertedWith("Initial funding required");
    });

    it("should revert if voting is already open", async function () {
      await quadraticVoting
        .connect(owner)
        .openVoting({ value: ethers.parseEther("1") });

      await expect(
        quadraticVoting
          .connect(owner)
          .openVoting({ value: ethers.parseEther("1") })
      ).to.be.revertedWith("Voting already open");
    });
  });

  describe("participant management", function () {
    it("should return the correct participant count", async function () {
      // initially zero
      expect(await quadraticVoting.getParticipantCount()).to.equal(0);

      // register two participants
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: tokenPrice });

      await quadraticVoting
        .connect(otherAccount)
        .addParticipant({ value: tokenPrice });

      // now count should be 2
      expect(await quadraticVoting.getParticipantCount()).to.equal(2);
    });
  });

  describe("Proposal Funding Count", function () {
    it("should correctly count proposals awaiting funding", async function () {
      // 1) Open voting
      await quadraticVoting
        .connect(owner)
        .openVoting({ value: ethers.parseEther("1") });

      // 2) Register two participants
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: tokenPrice });
      await quadraticVoting
        .connect(otherAccount)
        .addParticipant({ value: tokenPrice });

      // 3) Deploy a mock proposal contract (from mockProposal.sol)
      const Mock = await ethers.getContractFactory("MockProposal");
      const mock = await Mock.deploy();
      await mock.waitForDeployment();

      // 4) Add one funding proposal (budget > 0) and one signaling proposal (budget == 0)
      await quadraticVoting
        .connect(participant)
        .addProposal(
          "Fund Me",
          "Give me ETH",
          ethers.parseEther("0.2"),
          mock.target
        );

      await quadraticVoting
        .connect(participant)
        .addProposal("Just a Signal", "No budget", 0, mock.target);

      // 5) Only the first should count towards pending‐funding
      const pending = await quadraticVoting.getPendingProposals();
      expect(pending.length).to.equal(1);
    });
  });

  describe("participant management", function () {
    it("should return the correct participant count", async function () {
      // initially zero
      expect(await quadraticVoting.getParticipantCount()).to.equal(0);

      // register two participants
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: tokenPrice });

      await quadraticVoting
        .connect(otherAccount)
        .addParticipant({ value: tokenPrice });

      // now count should be 2
      expect(await quadraticVoting.getParticipantCount()).to.equal(2);
    });
  });

  describe("Proposal Funding Count", function () {
    it("should correctly count proposals awaiting funding", async function () {
      // 1) Open voting
      await quadraticVoting
        .connect(owner)
        .openVoting({ value: ethers.parseEther("1") });

      // 2) Register two participants
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: tokenPrice });
      await quadraticVoting
        .connect(otherAccount)
        .addParticipant({ value: tokenPrice });

      // 3) Deploy a mock proposal contract (from mockProposal.sol)
      const Mock = await ethers.getContractFactory("MockProposal");
      const mock = await Mock.deploy();
      await mock.waitForDeployment();

      // 4) Add one funding proposal (budget > 0) and one signaling proposal (budget == 0)
      await quadraticVoting
        .connect(participant)
        .addProposal(
          "Fund Me",
          "Give me ETH",
          ethers.parseEther("0.2"),
          mock.target
        );

      await quadraticVoting
        .connect(participant)
        .addProposal("Just a Signal", "No budget", 0, mock.target);

      // 5) Only the first should count towards pending‐funding
      const pending = await quadraticVoting.getPendingProposals();
      expect(pending.length).to.equal(1);
    });
  });

  describe("Participant Registration", function () {
    let tokenPrice;
    let maxTokens;

    beforeEach(async function () {
      [owner, participant, otherAccount] = await ethers.getSigners();
      tokenPrice = ethers.parseEther("0.1"); // Example token price in ether
      maxTokens = 1000000; // Max tokens set to a large number

      // Deploy VotingToken contract
      const Token = await ethers.getContractFactory("VotingToken");
      votingToken = await Token.deploy(0); // Initialize with 0 supply
      await votingToken.waitForDeployment();

      // Deploy QuadraticVoting contract
      const QV = await ethers.getContractFactory("QuadraticVoting");
      quadraticVoting = await QV.deploy(tokenPrice, maxTokens); // Max tokens set to a large number
      await quadraticVoting.waitForDeployment();
    });

    it("should allow a participant to register and mint tokens", async function () {
      const oneEth = ethers.parseEther("1");

      const participantInitialBalance = await ethers.provider.getBalance(
        participant.address
      );

      // Register the participant and check that they receive tokens
      await expect(
        quadraticVoting.connect(participant).addParticipant({ value: oneEth })
      )
        .to.emit(quadraticVoting, "ParticipantRegistered")
        .withArgs(
          participant.address,
          oneEth / tokenPrice,
          oneEth % tokenPrice
        );

      // Check that the participant has the correct number of tokens minted
      // grab the token instance that QuadraticVoting uses
      const tokenAddress = await quadraticVoting.getERC20();
      const onChainToken = await ethers.getContractAt(
        "VotingToken",
        tokenAddress
      );

      // now query that one
      const participantTokenBalance = await onChainToken.balanceOf(
        participant.address
      );

      expect(participantTokenBalance).to.equal(oneEth / tokenPrice);

      // Check that the participant count has increased
      expect(await quadraticVoting.getParticipantCount()).to.equal(1);

      // Ensure excess ETH is refunded correctly
      const participantFinalBalance = await ethers.provider.getBalance(
        participant.address
      );
      const excess = oneEth % tokenPrice;
      if (excess > 0) {
        expect(participantFinalBalance).to.equal(
          participantInitialBalance.add(excess)
        );
      }
    });

    it("should revert if insufficient Ether is sent", async function () {
      await expect(
        quadraticVoting
          .connect(participant)
          .addParticipant({ value: ethers.parseEther("0.05") })
      ).to.be.revertedWith("Insufficient Ether to buy at least 1 token");
    });

    it("should revert if participant is already registered", async function () {
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: ethers.parseEther("1") });

      await expect(
        quadraticVoting
          .connect(participant)
          .addParticipant({ value: ethers.parseEther("1") })
      ).to.be.revertedWith("Already registered");
    });

    it("should revert if registering exceeds the token cap", async function () {
      // -  // Deploy with a low max token cap to trigger the revert
      // -  const QV = await ethers.getContractFactory("QuadraticVoting");
      // -  const quadraticVotingWithCap = await QV.deploy(tokenPrice, maxTokens);
      // Deploy with a low max token cap to trigger the revert
      const lowCap = 5; // minting 10 tokens from 1 ETH at 0.1 ETH each will exceed this
      const QV = await ethers.getContractFactory("QuadraticVoting");
      const quadraticVotingWithCap = await QV.deploy(tokenPrice, lowCap);
      await quadraticVotingWithCap.waitForDeployment();

      await expect(
        quadraticVotingWithCap
          .connect(otherAccount)
          .addParticipant({ value: ethers.parseEther("1") })
      ).to.be.revertedWith("Token cap exceeded");
    });

    it("should refund excess Ether if more than needed is sent", async function () {
      const oneEth = ethers.parseEther("1.0"); // 1 ETH
      const excess = ethers.parseEther("0.05"); // 0.05 ETH

      const totalSent = oneEth + excess; // 1.05 ETH
      const tokensMinted = oneEth / tokenPrice; // 10 tokens at 0.1 ETH each
      const expectedContractBalance = oneEth; // should be exactly 1 ETH

      // call addParticipant with 1.05 ETH
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: totalSent });

      // now the contract should only have received 1 ETH (the cost of the tokens)
      const contractBal = await ethers.provider.getBalance(
        quadraticVoting.target
      );
      expect(contractBal).to.equal(expectedContractBalance);
    });
  });

  describe("removeParticipant", function () {
    it("should allow a registered participant to deregister and refund their ETH and burn their tokens", async function () {
      const deposit = tokenPrice * 5n;
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: deposit });

      // verify participant is registered and has 5 tokens
      expect(await quadraticVoting.getParticipantCount()).to.equal(1);
      const tokenAddr = await quadraticVoting.getERC20();
      const onChainToken = await ethers.getContractAt("VotingToken", tokenAddr);
      expect(await onChainToken.balanceOf(participant.address)).to.equal(5);

      // capture balances before removal
      const contractBalBefore = await ethers.provider.getBalance(
        quadraticVoting.target
      );

      // remove participant
      const tx = await quadraticVoting.connect(participant).removeParticipant();
      await tx.wait();

      // participantCount decremented
      expect(await quadraticVoting.getParticipantCount()).to.equal(0);

      // their token balance is now zero
      expect(await onChainToken.balanceOf(participant.address)).to.equal(0);

      // contract balance decreased by exactly 0.5 ETH
      const contractBalAfter = await ethers.provider.getBalance(
        quadraticVoting.target
      );
      expect(contractBalBefore - contractBalAfter).to.equal(deposit);
    });

    it("should revert if caller is not a participant", async function () {
      await expect(
        quadraticVoting.connect(otherAccount).removeParticipant()
      ).to.be.revertedWith("Not a participant");
    });

    it("should revert if participant has locked tokens", async function () {
      // open voting so stake can happen
      await quadraticVoting
        .connect(owner)
        .openVoting({ value: ethers.parseEther("1") });

      // register & approve tokens
      const deposit = tokenPrice * 3n;
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: deposit });
      const tokenAddr = await quadraticVoting.getERC20();
      const onChainToken = await ethers.getContractAt("VotingToken", tokenAddr);
      await onChainToken
        .connect(participant)
        .approve(quadraticVoting.target, 1);

      // add a dummy proposal to be able to stake
      const Mock = await ethers.getContractFactory("MockProposal");
      const mock = await Mock.deploy();
      await quadraticVoting
        .connect(participant)
        .addProposal("P1", "desc", 0, mock.target);

      // stake 1 vote (cost = 1 token^2)
      await onChainToken
        .connect(participant)
        .approve(quadraticVoting.target, 1);
      await quadraticVoting.connect(participant).stake(1, 1);

      // now lockedTokens[participant] = 1, so removeParticipant must revert
      await expect(
        quadraticVoting.connect(participant).removeParticipant()
      ).to.be.revertedWith("Must withdraw all votes first");
    });
  });

  describe("buyTokens", function () {
    beforeEach(async function () {
      // register the participant so they pass the onlyParticipant check
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: ethers.parseEther("0.1") });
    });

    it("should revert if caller is not a participant", async function () {
      await expect(
        quadraticVoting.connect(otherAccount).buyTokens({ value: tokenPrice })
      ).to.be.revertedWith("Not a participant");
    });

    it("should revert if insufficient Ether is sent", async function () {
      const tooLittle = tokenPrice - 1n;
      await expect(
        quadraticVoting.connect(participant).buyTokens({ value: tooLittle })
      ).to.be.revertedWith("Not enough Ether");
    });

    it("should mint the correct number of tokens", async function () {
      // send exactly 3 tokens worth
      const toSend = tokenPrice * 3n;
      await quadraticVoting.connect(participant).buyTokens({ value: toSend });

      const tokenAddr = await quadraticVoting.getERC20();
      const onChainToken = await ethers.getContractAt("VotingToken", tokenAddr);
      // initial mint from addParticipant was 1 token
      expect(await onChainToken.balanceOf(participant.address)).to.equal(
        1n + 3n
      );
    });

    it("should refund any excess Ether", async function () {
      const oneEth = ethers.parseEther("1"); // bigint
      const excess = ethers.parseEther("0.05"); // bigint
      const totalSent = oneEth + excess; // bigint

      // make sure participant has enough ETH to cover both the value and gas
      await owner.sendTransaction({
        to: participant.address,
        value: totalSent,
      });

      const bal0 = await ethers.provider.getBalance(participant.address); // bigint

      const tx = await quadraticVoting
        .connect(participant)
        .buyTokens({ value: totalSent });
      const receipt = await tx.wait();

      // receipt.cumulativeGasUsed is a bigint
      // Try to use receipt.effectiveGasPrice (bigint), but fall back to tx.gasPrice (BigNumber)
      let gasPrice;
      if (receipt.effectiveGasPrice != null) {
        gasPrice = receipt.effectiveGasPrice; // already a bigint
      } else {
        // tx.gasPrice is an ethers.BigNumber → convert to bigint
        gasPrice = BigInt(tx.gasPrice.toString());
      }

      const gasCost = receipt.cumulativeGasUsed * gasPrice; // bigint

      const bal1 = await ethers.provider.getBalance(participant.address); // bigint

      // The participant spent (oneEth) + (gasCost), so bal0 - bal1 should equal that
      expect(bal0 - bal1).to.equal(oneEth + gasCost);
    });

    it("should revert if minting would exceed the token cap", async function () {
      // deploy fresh with small cap = 2 tokens
      const QV = await ethers.getContractFactory("QuadraticVoting");
      const smallCap = 2n;
      const qv2 = await QV.deploy(tokenPrice, smallCap);
      await qv2.waitForDeployment();
      // register once: consumes 1 token
      await qv2.connect(participant).addParticipant({ value: tokenPrice });
      // now buying 2 more would exceed cap
      await expect(
        qv2.connect(participant).buyTokens({ value: tokenPrice * 2n })
      ).to.be.revertedWith("Token cap exceeded");
    });
  });

  describe("sellTokens", function () {
    beforeEach(async function () {
      // register the participant so they pass the onlyParticipant check
      await quadraticVoting
        .connect(participant)
        .addParticipant({ value: tokenPrice * 5n }); // mint 5 tokens
    });

    it("should revert if caller is not a participant", async function () {
      await expect(
        quadraticVoting.connect(otherAccount).sellTokens(1n)
      ).to.be.revertedWith("Not a participant");
    });

    it("should revert if selling zero tokens", async function () {
      await expect(
        quadraticVoting.connect(participant).sellTokens(0n)
      ).to.be.revertedWith("Cannot sell zero tokens");
    });

    it("should revert if selling more than free balance", async function () {
      const tokenAddr = await quadraticVoting.getERC20();
      const onChainToken = await ethers.getContractAt("VotingToken", tokenAddr);

      // 1) open voting & create a dummy signaling proposal so we can stake
      await quadraticVoting
        .connect(owner)
        .openVoting({ value: ethers.parseEther("1") });
      const Mock = await ethers.getContractFactory("MockProposal");
      const mock = await Mock.deploy();
      await mock.waitForDeployment();
      await quadraticVoting
        .connect(participant)
        .addProposal("Sig", "signal", 0, mock.target);

      // 2) stake 2 votes → cost = 2² = 4 tokens locked, so freeBalance = 5 - 4 = 1

      await onChainToken
        .connect(participant)
        .approve(quadraticVoting.target, 4n);
      await quadraticVoting.connect(participant).stake(1, 2n);

      // 3) now try to sell 2 tokens (more than the single free token) → should revert
      await expect(
        quadraticVoting.connect(participant).sellTokens(2n)
      ).to.be.revertedWith("Cannot sell locked tokens");
    });

    it("should burn tokens and refund Ether for valid sale", async function () {
      const sellAmount = 2n;
      const refund = sellAmount * tokenPrice;

      // capture balances before sale
      const tokenAddr = await quadraticVoting.getERC20();
      const onChainToken = await ethers.getContractAt("VotingToken", tokenAddr);
      const tokenBalBefore = await onChainToken.balanceOf(participant.address);
      expect(tokenBalBefore).to.equal(5n);

      const ethBalBefore = await ethers.provider.getBalance(
        participant.address
      );

      // perform sale
      const tx = await quadraticVoting
        .connect(participant)
        .sellTokens(sellAmount);
      const receipt = await tx.wait();

      // recompute gas cost
      let gasPrice;
      if (receipt.effectiveGasPrice != null) {
        gasPrice = receipt.effectiveGasPrice;
      } else {
        gasPrice = BigInt(tx.gasPrice.toString());
      }
      const gasCost = receipt.cumulativeGasUsed * gasPrice;

      // token balance decremented
      const tokenBalAfter = await onChainToken.balanceOf(participant.address);
      expect(tokenBalAfter).to.equal(5n - sellAmount);

      // ether refunded minus gas
      const ethBalAfter = await ethers.provider.getBalance(participant.address);
      // they gained `refund` but spent `gasCost`
      expect(ethBalAfter).to.equal(ethBalBefore + refund - gasCost);
    });
  });
});
