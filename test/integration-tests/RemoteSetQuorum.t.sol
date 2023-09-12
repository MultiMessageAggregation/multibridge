// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";

import {MultiMessageSender} from "src/MultiMessageSender.sol";
import {MultiMessageReceiver} from "src/MultiMessageReceiver.sol";
import {Error} from "src/libraries/Error.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

/// @dev scenario: admin updates quorum on dst chain using message from source chain
contract RemoteQuorumUpdate is Setup {
    /// @dev intializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just set remote chain quorum to 1 from 2 (done in setup)
    function test_remoteQuorumUpdate() public {
        uint256 newQuorum = 1;

        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137,
            address(contractAddress[137][bytes("MMA_RECEIVER")]),
            abi.encodeWithSelector(MultiMessageReceiver.updateQuorum.selector, newQuorum),
            0,
            block.timestamp + EXPIRATION_CONSTANT
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        vm.recordLogs();

        /// simulate off-chain actors
        _simulatePayloadDelivery(1, 137, logs);
        bytes32 msgId = _getMsgId(vm.getRecordedLogs());

        vm.selectFork(fork[137]);
        vm.recordLogs();
        /// execute the message and move it to governance timelock contract
        MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).executeMessage(msgId);
        (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta) =
            _getExecParams(vm.getRecordedLogs());

        uint256 oldQuorum = MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).quorum();
        assertEq(oldQuorum, 2);

        /// increment the time by 2 day (delay time)
        vm.warp(block.timestamp + 2 days);
        GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );

        uint256 currQuorum = MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).quorum();
        assertEq(currQuorum, newQuorum);
    }
}
