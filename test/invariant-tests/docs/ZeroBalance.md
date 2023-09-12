## Introduction
A key invariant for the `MultiMessageSender.sol`, and `GovernanceTimelock.sol` contracts are that it can never hold any value. It's `msg.value` should be zero always to make sure the refunding mechanisms are properly in place.

`MultiMessageReceiver.sol` have no receive() or payable functions to test this invariant