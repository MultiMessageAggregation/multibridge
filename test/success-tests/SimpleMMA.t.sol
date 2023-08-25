// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../Setup.t.sol";
import "../mock/MockUniswapReceiver.sol";
import {MultiMessageSender} from "src/MultiMessageSender.sol";
import {MultiMessageReceiver} from "src/MultiMessageReceiver.sol";

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
        console.logBytes32(msgId);

        vm.selectFork(fork[137]);

        /// execute message received
        vm.expectRevert(Error.MSG_STILL_TIMELOCKED.selector);
        MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).executeMessage(msgId);
        assertEq(target.i(), 0);

        /// increment the time by 1 day
        vm.warp(block.timestamp + 1 days);
        MultiMessageReceiver(contractAddress[137][bytes("MMA_RECEIVER")]).executeMessage(msgId);
        assertEq(target.i(), type(uint256).max);
    }
}
