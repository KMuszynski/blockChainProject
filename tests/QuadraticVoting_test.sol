// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "remix_tests.sol"; // Remix unit testing library
import "../quadraticVoting.sol"; // Make sure you import the correct contract paths
import "../IExecutableProposal.sol"; // Import the interface for IExecutableProposal
import "../mockProposal.sol"; // Import the MockProposal contract

contract QuadraticVotingTest {
    QuadraticVoting voting;
    VotingToken token;
    MockProposal mock;

    address owner;
    address user1;
    address user2;

    /// Setup
    function beforeAll() public {
        voting = new QuadraticVoting(1 ether, 100); // Initialize with token price and cap
        token = voting.getERC20(); // Get the token instance from the contract
        mock = new MockProposal(); // Initialize the mock proposal contract

        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
    }

    // Test 0: test test
function testTest() public payable {
    // Ensure voting is closed before the test
    Assert.equal(true, true, "1 should be equal to 1");
}

function testVotingClosed() public payable {
    // Ensure voting is closed before the test
    Assert.equal(voting.getVotingStatus(), false, "Voting should initially be closed");

}

    // Test 1: Open voting
function testOpenVoting() public payable {
    // Ensure voting is closed before the test
    Assert.equal(voting.getVotingStatus(), false, "Voting should initially be closed");

    // Now call the openVoting function
    voting.openVoting{value: 10 ether}();
    
    // Ensure voting is now open
    Assert.equal(voting.getVotingStatus(), true, "Voting should be open after calling openVoting");
}


}
