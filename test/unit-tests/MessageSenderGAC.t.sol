// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// local imports
import "../Setup.t.sol";
import "../contracts-mock/FailingSenderAdapter.sol";
import "../contracts-mock/ZeroAddressReceiverGAC.sol";
import "../../src/interfaces/adapters/IMessageSenderAdapter.sol";
import "src/interfaces/IMultiBridgeMessageReceiver.sol";
import "../../src/interfaces/controllers/IGAC.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";

contract MessageSenderGACTest is Setup {
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event MultiBridgeMessageCallerUpdated(address indexed oldAuthCaller, address indexed newAuthCaller);
    event MultiBridgeMessageSenderUpdated(address indexed oldMMS, address indexed newMMS);
    event MultiBridgeMessageReceiverUpdated(uint256 indexed chainId, address indexed oldMMR, address indexed newMMR);

    address senderAddr;
    address receiverAddr;
    MessageSenderGAC senderGAC;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        senderAddr = contractAddress[SRC_CHAIN_ID]["MMA_SENDER"];
        receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        senderGAC = MessageSenderGAC(contractAddress[SRC_CHAIN_ID]["GAC"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(Ownable(address(senderGAC)).owner()), owner);
    }

    /// @dev sets multi message sender
    function test_set_multi_message_sender() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(senderGAC));
        emit MultiBridgeMessageSenderUpdated(senderGAC.multiBridgeMessageSender(), address(42));

        senderGAC.setMultiBridgeMessageSender(address(42));

        assertEq(senderGAC.multiBridgeMessageSender(), address(42));
    }

    /// @dev only owner can set multi message sender
    function test_set_multi_message_sender_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        senderGAC.setMultiBridgeMessageSender(address(42));
    }

    /// @dev cannot set multi message sender to zero address
    function test_set_multi_message_sender_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        senderGAC.setMultiBridgeMessageSender(address(0));
    }

    /// @dev sets multi message caller
    function test_set_multi_message_caller() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(senderGAC));
        emit MultiBridgeMessageCallerUpdated(senderGAC.authorisedCaller(), address(42));

        senderGAC.setAuthorisedCaller(address(42));

        assertEq(senderGAC.authorisedCaller(), address(42));
    }

    /// @dev only owner can set multi message caller
    function test_set_multi_message_caller_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        senderGAC.setAuthorisedCaller(address(42));
    }

    /// @dev cannot set multi message caller to zero address
    function test_set_multi_message_caller_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        senderGAC.setAuthorisedCaller(address(0));
    }

    /// @dev sets multi message receiver
    function test_set_multi_message_receiver() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(senderGAC));
        emit MultiBridgeMessageReceiverUpdated(
            DST_CHAIN_ID, senderGAC.remoteMultiBridgeMessageReceiver(DST_CHAIN_ID), address(42)
        );

        senderGAC.setRemoteMultiBridgeMessageReceiver(DST_CHAIN_ID, address(42));

        assertEq(senderGAC.remoteMultiBridgeMessageReceiver(DST_CHAIN_ID), address(42));
    }

    /// @dev only owner can set multi message receiver
    function test_set_multi_message_receiver_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        senderGAC.setRemoteMultiBridgeMessageReceiver(DST_CHAIN_ID, address(42));
    }

    /// @dev cannot set multi message receiver to zero address
    function test_set_multi_message_receiver_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        senderGAC.setRemoteMultiBridgeMessageReceiver(DST_CHAIN_ID, address(0));
    }

    /// @dev cannot set multi message receiver on zero chain ID
    function test_set_multi_message_receiver_zero_chain_id() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        senderGAC.setRemoteMultiBridgeMessageReceiver(0, address(42));
    }

    /// @dev sets global message delivery gas limit
    function test_set_global_msg_delivery_gas_limit() public {
        vm.startPrank(owner);

        uint256 oldLimit = senderGAC.msgDeliveryGasLimit();
        vm.expectEmit(true, true, true, true, address(senderGAC));
        emit DstGasLimitUpdated(oldLimit, 420000);

        senderGAC.setGlobalMsgDeliveryGasLimit(420000);

        assertEq(senderGAC.msgDeliveryGasLimit(), 420000);
    }

    /// @dev only owner can set global message delivery gas limit
    function test_set_global_msg_delivery_gas_limit_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        senderGAC.setGlobalMsgDeliveryGasLimit(420000);
    }

    /// @dev cannot set a gas limit lower than the minimum
    function test_set_global_msg_delivery_gas_limit_lower_than_min() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.INVALID_DST_GAS_LIMIT_MIN.selector);
        senderGAC.setGlobalMsgDeliveryGasLimit(30000);
    }

    /// @dev checks if address is the global owner
    function test_is_global_owner() public {
        assertTrue(senderGAC.isGlobalOwner(owner));
        assertFalse(senderGAC.isGlobalOwner(caller));
    }

    /// @dev gets the global owner
    function test_get_global_owner() public {
        assertEq(senderGAC.getGlobalOwner(), owner);
    }
}
