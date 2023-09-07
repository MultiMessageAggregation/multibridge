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

/// @dev scenario: demonstrate that a admin-specified deadline is good
contract MessageDeadlineCheck is Setup {
    struct TxVars {
        uint256 txId;
        address finalTarget;
        uint256 value;
        bytes data;
        uint256 eta;
    }

    TxVars public adapterRemoveTx;
    bytes32 public maliciousMsgId;

    /// @dev intializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just sends a message
    function test_messageDeadlineCheck() public {
        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        /// from chain Ethereum uniswap passes a governance proposal to remove wormhole
        /// this would fail, since quorum should be reduced before remove adapter
        _removeAdapter();

        vm.selectFork(fork[1]);
        vm.startPrank(caller);
        /// malicious governance actor queues up a malicious tx to re-update wormhole before wormhole
        /// passes the quorum update proposal through just one message bridge
        _queueMaliciousAdapterAdd();

        vm.selectFork(fork[1]);
        vm.startPrank(caller);
        /// now if uniswap governace queues up the quorum update transaction
        _quorumUpdateTx();

        /// now the user tries to execute his old msg id which didn't pass quorum
        /// NOTE: this will revert here; but with a user specified eta / expiry this might pass
        vm.expectRevert(Error.MSG_EXECUTION_PASSED_DEADLINE.selector);
        MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).executeMessage(maliciousMsgId);
    }

    function _removeAdapter() internal {
        address[] memory adaptersToRemove = new address[](1);
        adaptersToRemove[0] = contractAddress[137]["WORMHOLE_RECEIVER_ADAPTER"];

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](1);
        operation[0] = false;

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137,
            address(contractAddress[137][bytes("MMA_RECEIVER")]),
            abi.encodeWithSelector(MultiMessageReceiver.updateReceiverAdapter.selector, adaptersToRemove, operation),
            0
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

        adapterRemoveTx = TxVars(txId, finalTarget, value, data, eta);

        /// increment the time by 2 day (delay time)
        vm.warp(block.timestamp + 2 days);

        /// CRITICAL NOTE: reverts due to quorum validation failure.
        /// this could mess up the quorum.
        /// If quorum is reduced before removing the colluded receiver, then the non-quorum reached messages could be replayed.
        vm.expectRevert(Error.EXECUTION_FAILS_ON_DST.selector);
        GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );
    }

    function _queueMaliciousAdapterAdd() internal {
        address[] memory adaptersToRemove = new address[](1);
        adaptersToRemove[0] = contractAddress[137]["WORMHOLE_RECEIVER_ADAPTER"];

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](1);
        operation[0] = false;

        address[] memory excludeAxelar = new address[](1);
        excludeAxelar[0] = contractAddress[1]["AXELAR_SENDER_ADAPTER"];

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137,
            address(contractAddress[137][bytes("MMA_RECEIVER")]),
            abi.encodeWithSelector(MultiMessageReceiver.updateReceiverAdapter.selector, adaptersToRemove, operation),
            0,
            excludeAxelar
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        vm.recordLogs();
        /// simulate off-chain actors
        _simulatePayloadDelivery(1, 137, logs);
        maliciousMsgId = _getMsgId(vm.getRecordedLogs());

        vm.selectFork(fork[137]);

        /// execute the message but will fail due to insufficient quorum

        vm.expectRevert(Error.INVALID_QUORUM_FOR_EXECUTION.selector);
        MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).executeMessage(maliciousMsgId);
    }

    function _quorumUpdateTx() internal {
        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137,
            address(contractAddress[137][bytes("MMA_RECEIVER")]),
            abi.encodeWithSelector(MultiMessageReceiver.updateQuorum.selector, 1),
            0
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

        /// increment the time by 2 day (delay time)
        vm.warp(block.timestamp + 2 days);

        /// when quorum is updated here
        GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );
    }
}
