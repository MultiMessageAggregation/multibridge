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
/// @notice handles both single add and multiple remove
contract RemoteAdapterRemove is Setup {
    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();
    }

    /// @dev just remove one adapter and assert
    function test_remoteRemoveReceiverAdapterSingle() public {
        address[] memory adaptersToRemove = new address[](1);
        adaptersToRemove[0] = contractAddress[DST_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"];

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](1);
        operation[0] = false;

        uint256 newQuorum = 1;

        _adapterRemove(newQuorum, adaptersToRemove, operation);
    }

    /// @dev add multiple adapters and assert
    function test_remoteRemoveReceiverAdapterMulti() public {
        /// @dev adds a dummy adapter since quorum threshold can never be 0
        _updateDummy();

        address[] memory adaptersToRemove = new address[](2);
        adaptersToRemove[0] = contractAddress[DST_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"];
        adaptersToRemove[1] = contractAddress[DST_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"];

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](2);
        operation[0] = false;
        operation[1] = false;

        uint256 newQuorum = 1;

        _adapterRemove(newQuorum, adaptersToRemove, operation);
    }

    function _adapterRemove(uint256 newQuorum, address[] memory adaptersToRemove, bool[] memory operation) internal {
        vm.selectFork(fork[ETHEREUM_CHAIN_ID]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            DST_CHAIN_ID,
            address(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]),
            abi.encodeWithSelector(
                MultiMessageReceiver.updateQuorumAndReceiverAdapter.selector, newQuorum, adaptersToRemove, operation
            ),
            0,
            EXPIRATION_CONSTANT
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

        /// increment the time by 7 days (delay time)
        vm.warp(block.timestamp + 7 days);
        GovernanceTimelock(contractAddress[DST_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );

        /// @dev validates quorum post update
        uint256 currQuorum = MultiMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]).quorum();
        assertEq(currQuorum, newQuorum);

        /// @dev validates adapters post update
        for (uint256 j; j < adaptersToRemove.length; ++j) {
            bool isTrusted = MultiMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")])
                .isTrustedExecutor(adaptersToRemove[j]);
            assert(!isTrusted);
        }
    }

    function _updateDummy() internal {
        address[] memory newDummyAdapter = new address[](1);
        newDummyAdapter[0] = address(420);

        /// true = add
        /// false = remove
        bool[] memory operation = new bool[](1);
        operation[0] = true;

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        MultiMessageReceiver(contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"]).updateReceiverAdapters(
            newDummyAdapter, operation
        );
        vm.stopPrank();
    }
}
