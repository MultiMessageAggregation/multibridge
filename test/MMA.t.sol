// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "./Setup.t.sol";

/// local imports
import {MultiMessageSender} from "../src/MultiMessageSender.sol";

contract MMA is Setup {
    /// @dev intializes the setup
    function setUp() public override {
        super.setUp();
    }

    function test_mma_send() public virtual {
        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            137,
            contractAddress[137][bytes("MMA_RECEIVER")],
            contractAddress[137][bytes("MMA_RECEIVER")],    /// FIXME: move to uniswap timelock
            bytes(""),
            uint64(block.timestamp + 2 days)
        );
    }
} 