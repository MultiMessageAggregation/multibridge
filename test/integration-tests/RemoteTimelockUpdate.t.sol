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

/// @dev scenario: admin updates timelock delay on dst chain using message from source chain
contract RemoteTimelockUpdate is Setup {
    /// @dev intializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just set timelock delay to 19 days and assert
    function test_remoteTimelockUpdate() public {
        uint256 newDelay = 19 days;

        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137,
            address(contractAddress[137][bytes("TIMELOCK")]),
            abi.encodeWithSelector(GovernanceTimelock.setDelay.selector, newDelay),
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

        uint256 oldDelay = GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).delay();
        assertEq(oldDelay, GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).MINIMUM_DELAY());

        /// increment the time by 2 day (delay time)
        vm.warp(block.timestamp + 2 days);
        GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );

        uint256 currDelay = GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).delay();
        assertEq(currDelay, newDelay);
    }
}
