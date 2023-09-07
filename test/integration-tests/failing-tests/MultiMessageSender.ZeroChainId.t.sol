// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../Setup.t.sol";
import "../../contracts-mock/MockUniswapReceiver.sol";

import {MultiMessageSender} from "src/MultiMessageSender.sol";
import {MultiMessageReceiver} from "src/MultiMessageReceiver.sol";
import {Error} from "src/libraries/Error.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

contract ZeroChainId is Setup {
    MockUniswapReceiver target;

    /// @dev intializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[137]);
        target = new MockUniswapReceiver();
    }

    /// @dev just sends a message
    function test_zeroChainId() public {
        vm.selectFork(fork[1]);
        vm.startPrank(caller);

        /// send cross-chain message using MMA infra
        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        MultiMessageSender(contractAddress[1][bytes("MMA_SENDER")]).remoteCall{value: 2 ether}(
            0, address(target), abi.encode(MockUniswapReceiver.setValue.selector, ""), 0
        );
    }
}
