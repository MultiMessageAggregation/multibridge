// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

/// local imports
import "test/Setup.t.sol";
import "test/contracts-mock/MockUniswapReceiver.sol";

import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";
import {MultiBridgeMessageReceiver} from "src/MultiBridgeMessageReceiver.sol";
import {Error} from "src/libraries/Error.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

/// @dev scenario 1: tries to execute the txId before timelock ends
/// @dev scenario 2: tries to execute the txId post timelock ends and within expiry
contract TimelockCheckTest is Setup {
    MockUniswapReceiver target;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        target = new MockUniswapReceiver();
    }

    /// @dev just sends a message
    function test_timelockCheck() public {
        vm.selectFork(fork[SRC_CHAIN_ID]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        uint256[] memory fees = new uint256[](2);
        (uint256 wormholeFee,) =
            IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(_wormholeChainId(DST_CHAIN_ID), 0, 0);
        fees[0] = wormholeFee;
        fees[1] = 0.01 ether;
        MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            DST_CHAIN_ID,
            address(target),
            abi.encode(MockUniswapReceiver.setValue.selector, ""),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees
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
        MultiBridgeMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]).executeMessage(msgId);
        (uint256 txId, address finalTarget, uint256 value, bytes memory data, uint256 eta) =
            _getExecParams(vm.getRecordedLogs());

        /// increment the time by 1 day (less than delay time)
        /// @notice should revert here with TX_TIMELOCKED error
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(Error.TX_TIMELOCKED.selector);
        GovernanceTimelock(contractAddress[DST_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );

        /// increment the time by 2 day (delay time)
        vm.warp(block.timestamp + 2 days);
        GovernanceTimelock(contractAddress[DST_CHAIN_ID][bytes("TIMELOCK")]).executeTransaction(
            txId, finalTarget, value, data, eta
        );
        assertEq(target.i(), type(uint256).max);
    }
}
