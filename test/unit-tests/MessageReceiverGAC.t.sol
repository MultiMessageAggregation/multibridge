// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// local imports
import "../Setup.t.sol";
import "../contracts-mock/ZeroAddressReceiverGAC.sol";
import "src/interfaces/IMultiMessageReceiver.sol";
import "src/interfaces/IGAC.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";

contract MessageReceiverGACTest is Setup {
    event MultiMessageReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    MessageReceiverGAC private receiverGAC;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();
        vm.selectFork(fork[DST_CHAIN_ID]);
        receiverGAC = MessageReceiverGAC(contractAddress[DST_CHAIN_ID]["GAC"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(Ownable(address(receiverGAC)).owner()), owner);
    }

    /// @dev sets multi message receiver
    function test_set_multi_message_receiver() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(receiverGAC));
        emit MultiMessageReceiverUpdated(address(receiverGAC.getMultiMessageReceiver()), address(42));

        receiverGAC.setMultiMessageReceiver(address(42));

        assertEq(receiverGAC.getMultiMessageReceiver(), address(42));
    }

    /// @dev only owner can set multi message receiver
    function test_set_multi_message_receiver_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        receiverGAC.setMultiMessageReceiver(address(42));
    }

    /// @dev cannot set multi message receiver to zero address
    function test_set_multi_message_receiver_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        receiverGAC.setMultiMessageReceiver(address(0));
    }

    /// @dev checks if address is the global owner
    function test_is_global_owner() public {
        assertTrue(receiverGAC.isGlobalOwner(owner));
        assertFalse(receiverGAC.isGlobalOwner(caller));
    }

    /// @dev gets the global owner
    function test_get_global_owner() public {
        assertEq(receiverGAC.getGlobalOwner(), owner);
    }
}
