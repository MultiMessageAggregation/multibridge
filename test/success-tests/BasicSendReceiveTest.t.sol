// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

// /// library imports
// import {Vm} from "forge-std/Test.sol";

// /// local imports
// import "../Setup.t.sol";
// import {MultiMessageSender} from "../../src/MultiMessageSender.sol";

// contract MMA is Setup {
//     /// @dev intializes the setup
//     function setUp() public override {
//         super.setUp();
//     }

//     /// @dev just sends a message
//     function test_mma_send_receive() public {
//         vm.selectFork(fork[1]);
//         vm.startPrank(caller);

//         vm.recordLogs();
//         MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
//             137,
//             contractAddress[137][bytes("MMA_RECEIVER")],
//             address(0),
//             /// FIXME: move to uniswap timelock
//             bytes(""),
//             uint64(block.timestamp + 2 days)
//         );

//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         vm.stopPrank();
//         _simulatePayloadDelivery(1, 137, logs);
//     }
// }
