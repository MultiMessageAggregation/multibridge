// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

/// local imports
import "test/Setup.t.sol";

import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";
import {MultiBridgeMessageReceiver} from "src/MultiBridgeMessageReceiver.sol";
import "src/libraries/Message.sol";
import {Error} from "src/libraries/Error.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

/// @dev scenario: admin updates quorum on dst chain using message from source chain
contract RemoteQuorumUpdate is Setup {
    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just set remote chain quorum to 1 from 2 (done in setup)
    function test_remoteQuorumUpdate() public {
        uint256 newQuorum = 1;

        vm.selectFork(fork[SRC_CHAIN_ID]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        (uint256 wormholeFee,) =
            IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(_wormholeChainId(DST_CHAIN_ID), 0, 0);
        (, uint256[] memory fees) = _sortTwoAdaptersWithFees(
            contractAddress[SRC_CHAIN_ID][bytes("AXELAR_SENDER_ADAPTER")],
            contractAddress[SRC_CHAIN_ID][bytes("WORMHOLE_SENDER_ADAPTER")],
            0.01 ether,
            wormholeFee
        );

        _sendAndExecuteMessage(newQuorum, fees);

        uint256 currQuorum = MultiBridgeMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]).quorum();
        assertEq(currQuorum, newQuorum);
    }

    function _sendAndExecuteMessage(uint256 newQuorum, uint256[] memory fees) private {
        address receiverAddr = contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")];
        bytes memory callData = abi.encodeWithSelector(MultiBridgeMessageReceiver.updateQuorum.selector, newQuorum);
        uint256 expiration = block.timestamp + EXPIRATION_CONSTANT;
        MultiBridgeMessageSender sender = MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]);
        uint256 nonce = sender.nonce() + 1;
        sender.remoteCall{value: 2 ether}(
            DST_CHAIN_ID,
            receiverAddr,
            callData,
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        vm.recordLogs();

        /// simulate off-chain actors
        _simulatePayloadDelivery(SRC_CHAIN_ID, DST_CHAIN_ID, logs);
        bytes32 msgId = _getMsgId(vm.getRecordedLogs());

        vm.selectFork(fork[DST_CHAIN_ID]);
        vm.recordLogs();
        /// schedule the message for execution by moving it to governance timelock contract
        MultiBridgeMessageReceiver(receiverAddr).scheduleMessageExecution(
            msgId,
            MessageLibrary.MessageExecutionParams({
                target: receiverAddr,
                callData: callData,
                value: 0,
                nonce: nonce,
                expiration: expiration
            })
        );
        (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta) =
            _getExecParams(vm.getRecordedLogs());

        uint256 oldQuorum = MultiBridgeMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]).quorum();
        assertEq(oldQuorum, 2);

        /// increment the time by 3 days (delay time)
        vm.warp(block.timestamp + 3 days);
        GovernanceTimelock(contractAddress[DST_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );
    }
}
