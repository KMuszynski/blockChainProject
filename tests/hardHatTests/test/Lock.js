const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Lock", function () {
  it("Should deploy and withdraw after unlockTime", async function () {
    const [owner] = await ethers.getSigners();
    const unlockTime = Math.floor(Date.now() / 1000) + 2; // 2 seconds in future
    const lockedAmount = ethers.parseEther("1");

    const Lock = await ethers.getContractFactory("Lock");
    const lock = await Lock.deploy(unlockTime, { value: lockedAmount });
    await lock.waitForDeployment();

    expect(await lock.unlockTime()).to.equal(unlockTime);

    // Wait 2+ seconds
    await new Promise((resolve) => setTimeout(resolve, 3000));

    const balanceBefore = await ethers.provider.getBalance(owner.address);
    const tx = await lock.withdraw();
    const receipt = await tx.wait();

    const balanceAfter = await ethers.provider.getBalance(owner.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
  });
});
