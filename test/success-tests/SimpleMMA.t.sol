// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../Setup.t.sol";
import "../mock/MockUniswapReceiver.sol";

import {MultiMessageSender} from "src/MultiMessageSender.sol";
import {MultiMessageReceiver} from "src/MultiMessageReceiver.sol";
import {Error} from "src/libraries/Error.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

contract MMA is Setup {
    MockUniswapReceiver target;

    /// @dev intializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[137]);
        target = new MockUniswapReceiver();
    }

    /// @dev just sends a message
    function test_mma_send_receive() public {
        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.recordLogs();
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137, address(target), abi.encode(MockUniswapReceiver.setValue.selector, "")
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        vm.recordLogs();
        /// simulate off-chain actors
        _simulatePayloadDelivery(1, 137, logs);

        Vm.Log[] memory msgIdLogs = vm.getRecordedLogs();

        bytes32 msgId;
        for (uint256 i; i < msgIdLogs.length; i++) {
            if (msgIdLogs[i].topics[0] == keccak256("SingleBridgeMsgReceived(bytes32,string,uint256,address)")) {
                msgId = msgIdLogs[i].topics[1];
            }
        }

        vm.selectFork(fork[137]);

        /// execute the message and move it to governance timelock contract
        MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).executeMessage(msgId);

        /// increment the time by 2 day (delay time)
        vm.warp(block.timestamp + 1 days);
        GovernanceTimelock(contractAddress[137][bytes("TIMELOCK")]).executeTransaction(1);
        assertEq(target.i(), type(uint256).max);
    }
}
