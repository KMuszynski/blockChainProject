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
});
