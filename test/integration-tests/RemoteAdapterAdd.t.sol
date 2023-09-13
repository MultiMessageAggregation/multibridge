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

    function _adapterAdd(address[] memory adaptersToAdd, bool[] memory operation) internal {
        vm.selectFork(fork[ETHEREUM_CHAIN_ID]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            DST_CHAIN_ID,
            address(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]),
            abi.encodeWithSelector(MultiMessageReceiver.updateReceiverAdapters.selector, adaptersToAdd, operation),
            0,
            block.timestamp + EXPIRATION_CONSTANT
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        vm.recordLogs();
        /// simulate off-chain actors
        _simulatePayloadDelivery(SRC_CHAIN_ID, DST_CHAIN_ID, logs);
        bytes32 msgId = _getMsgId(vm.getRecordedLogs());

        vm.selectFork(fork[DST_CHAIN_ID]);
        vm.recordLogs();
        /// execute the message and move it to governance timelock contract
        MultiMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]).executeMessage(msgId);
        (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta) =
            _getExecParams(vm.getRecordedLogs());

        /// increment the time by 3 days (delay time)
        vm.warp(block.timestamp + 3 days);
        GovernanceTimelock(contractAddress[DST_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );

        for (uint256 j; j < adaptersToAdd.length; ++j) {
            bool isTrusted = MultiMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")])
                .isTrustedExecutor(adaptersToAdd[j]);
            assert(isTrusted);
        }
    }
}
