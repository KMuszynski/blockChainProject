// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "remix_tests.sol"; // Remix testing library
import "remix_accounts.sol"; // To interact with accounts for testing
import "../votingToken.sol"; // Import the contract you're testing

contract VotingTokenTest {
    // Test: Check the token name
    function checkTokenName() public {
        VotingToken token = new VotingToken(1000);
        Assert.equal(
            token.name(),
            "VotingToken",
            "The name should be 'VotingToken'"
        );
    }

    // Test: Check the token symbol
    function checkTokenSymbol() public {
        VotingToken token = new VotingToken(1000);
        Assert.equal(token.symbol(), "VOTE", "The symbol should be 'VOTE'");
    }

    // Test: Check the initial total supply
    function checkInitialSupply() public {
        VotingToken token = new VotingToken(1000);
        Assert.equal(token.totalSupply(), 1000, "Total supply should be 1000");
    }

    // Test: Mint tokens to an external account and check balance
    function testMint() public {
        VotingToken token = new VotingToken(0);
        address recipient = TestsAccounts.getAccount(1);
        token.mint(recipient, 500);

        uint256 balance = token.balanceOf(recipient);
        Assert.equal(balance, 500, "The balance should be 500 tokens");
    }

    // Test: Burn tokens from an address and check balance
    function testBurn() public {
        VotingToken token = new VotingToken(0);
        address testAddress = TestsAccounts.getAccount(1);
        token.mint(testAddress, 500); // Mint 500 tokens to account 1

        uint256 balanceBeforeBurn = token.balanceOf(testAddress);
        token.burn(testAddress, 200); // Burn 200 tokens from account 1
        uint256 balanceAfterBurn = token.balanceOf(testAddress);

        Assert.equal(
            balanceAfterBurn,
            balanceBeforeBurn - 200,
            "The balance should decrease by 200 after burning 200 tokens"
        );
    }

    // Test: Transfer tokens from this contract's balance and check balances
    function testTransfer() public {
        VotingToken token = new VotingToken(0);
        address receiver = TestsAccounts.getAccount(2);

        // Mint directly to the test contract
        token.mint(address(this), 500);
        uint256 beforeSender = token.balanceOf(address(this));
        uint256 beforeReceiver = token.balanceOf(receiver);

        bool success = token.transfer(receiver, 200);
        Assert.equal(success, true, "Transfer should succeed");

        Assert.equal(
            token.balanceOf(address(this)),
            beforeSender - 200,
            "Sender (test contract) should lose 200"
        );
        Assert.equal(
            token.balanceOf(receiver),
            beforeReceiver + 200,
            "Receiver should gain 200"
        );
    }

    // Test: Ensure transfer fails when not enough balance in this contract
    function testTransferFails() public {
        VotingToken token = new VotingToken(0);
        address receiver = TestsAccounts.getAccount(2);

        // Mint fewer tokens than we try to send
        token.mint(address(this), 100);

        bool didFail = false;
        try token.transfer(receiver, 200) {
            // should not succeed
        } catch {
            didFail = true;
        }

        Assert.equal(
            didFail,
            true,
            "The transfer should fail due to insufficient balance"
        );
    }

    // Test: Ensure burn fails when not enough balance in this contract
    function testBurnFails() public {
        VotingToken token = new VotingToken(0);
        token.mint(address(this), 100);

        bool didFail = false;
        try token.burn(address(this), 200) {
            // should not succeed
        } catch {
            didFail = true;
        }

        Assert.equal(
            didFail,
            true,
            "Burning should fail as the balance is insufficient"
        );
    }
}
