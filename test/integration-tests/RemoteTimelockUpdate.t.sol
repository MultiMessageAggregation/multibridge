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
    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just set timelock delay to 19 days and assert
    function test_remoteTimelockUpdate() public {
        uint256 newDelay = 19 days;

        vm.selectFork(fork[SRC_CHAIN_ID]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            POLYGON_CHAIN_ID,
            address(contractAddress[POLYGON_CHAIN_ID][bytes("TIMELOCK")]),
            abi.encodeWithSelector(GovernanceTimelock.setDelay.selector, newDelay),
            0,
            block.timestamp + EXPIRATION_CONSTANT
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        vm.recordLogs();

        /// simulate off-chain actors
        _simulatePayloadDelivery(ETHEREUM_CHAIN_ID, POLYGON_CHAIN_ID, logs);
        bytes32 msgId = _getMsgId(vm.getRecordedLogs());

        vm.selectFork(fork[POLYGON_CHAIN_ID]);
        vm.recordLogs();
        /// execute the message and move it to governance timelock contract
        MultiMessageReceiver(contractAddress[POLYGON_CHAIN_ID][bytes("MMA_RECEIVER")]).executeMessage(msgId);
        (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta) =
            _getExecParams(vm.getRecordedLogs());

        uint256 oldDelay = GovernanceTimelock(contractAddress[POLYGON_CHAIN_ID][bytes("TIMELOCK")]).delay();
        assertEq(oldDelay, 3 days);

        /// increment the time by 3 days (delay time)
        vm.warp(block.timestamp + 3 days);
        GovernanceTimelock(contractAddress[POLYGON_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );

        uint256 currDelay = GovernanceTimelock(contractAddress[POLYGON_CHAIN_ID][bytes("TIMELOCK")]).delay();
        assertEq(currDelay, newDelay);
    }
}