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

/// @dev scenario: admin updates sender adapters on dst chain using message from source chain
/// @notice handles both single add and multiple add
contract RemoteAdapterAdd is Setup {
    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just add one adapter and assert
    function test_remoteAddReceiverAdapterSingle() public {
        address[] memory adaptersToAdd = new address[](1);
        adaptersToAdd[0] = address(420421422);

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](1);
        operation[0] = true;

        _adapterAdd(adaptersToAdd, operation);
    }

    /// @dev add multiple adapters and assert
    function test_remoteAddReceiverAdapterMulti() public {
        address[] memory adaptersToAdd = new address[](3);
        adaptersToAdd[0] = address(42042142232313);
        adaptersToAdd[1] = address(22132131);
        adaptersToAdd[2] = address(22132132131);

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](3);
        operation[0] = true;
        operation[1] = true;
        operation[2] = true;

        _adapterAdd(adaptersToAdd, operation);
    }

    function _adapterAdd(address[] memory adaptersToAdd, bool[] memory operation) private {
        vm.selectFork(fork[ETHEREUM_CHAIN_ID]);
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

        _sendAndExecuteMessage(adaptersToAdd, operation, fees);

        for (uint256 j; j < adaptersToAdd.length; ++j) {
            bool isTrusted = MultiBridgeMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")])
                .isTrustedExecutor(adaptersToAdd[j]);
            assert(isTrusted);
        }
    }

    function _sendAndExecuteMessage(address[] memory adaptersToAdd, bool[] memory operation, uint256[] memory fees)
        private
    {
        MultiBridgeMessageSender sender = MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]);
        uint256 nonce = sender.nonce() + 1;
        bytes memory callData =
            abi.encodeWithSelector(MultiBridgeMessageReceiver.updateReceiverAdapters.selector, adaptersToAdd, operation);
        uint256 expiration = block.timestamp + EXPIRATION_CONSTANT;
        sender.remoteCall{value: 2 ether}(
            DST_CHAIN_ID,
            contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")],
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
        MultiBridgeMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]).scheduleMessageExecution(
            msgId,
            MessageLibrary.MessageExecutionParams({
                target: contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")],
                callData: callData,
                value: 0,
                nonce: nonce,
                expiration: expiration
            })
        );
        (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta) =
            _getExecParams(vm.getRecordedLogs());

        /// increment the time by 3 days (delay time)
        vm.warp(block.timestamp + 3 days);
        GovernanceTimelock(contractAddress[DST_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );
    }
}
