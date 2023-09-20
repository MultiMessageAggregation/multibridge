// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// local imports
import "../Setup.t.sol";
import "../contracts-mock/FailingSenderAdapter.sol";
import "../contracts-mock/ZeroAddressReceiverGac.sol";
import "src/interfaces/IMessageSenderAdapter.sol";
import "src/interfaces/IMultiMessageReceiver.sol";
import "src/interfaces/ISenderGAC.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import {MultiMessageSender} from "src/MultiMessageSender.sol";

contract GACTest is Setup {
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event MultiMessageCallerUpdated(address indexed mmaCaller);
    event MultiMessageSenderUpdated(address indexed mmaSender);
    event MultiMessageReceiverUpdated(uint256 chainId, address indexed mmaReceiver);

    address senderAddr;
    address receiverAddr;
    ISenderGAC gac;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        senderAddr = contractAddress[SRC_CHAIN_ID]["MMA_SENDER"];
        receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        gac = ISenderGAC(contractAddress[SRC_CHAIN_ID]["GAC"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(Ownable(address(gac)).owner()), owner);
    }

    /// @dev sets multi message sender
    function test_set_multi_message_sender() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(gac));
        emit MultiMessageSenderUpdated(address(42));

        gac.setMultiMessageSender(address(42));

        assertEq(gac.getMultiMessageSender(), address(42));
    }

    /// @dev only owner can set multi message sender
    function test_set_multi_message_sender_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        gac.setMultiMessageSender(address(42));
    }

    /// @dev cannot set multi message sender to zero address
    function test_set_multi_message_sender_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        gac.setMultiMessageSender(address(0));
    }

    /// @dev sets multi message caller
    function test_set_multi_message_caller() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(gac));
        emit MultiMessageCallerUpdated(address(42));

        gac.setMultiMessageCaller(address(42));

        assertEq(gac.getMultiMessageCaller(), address(42));
    }

    /// @dev only owner can set multi message caller
    function test_set_multi_message_caller_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        gac.setMultiMessageCaller(address(42));
    }

    /// @dev cannot set multi message caller to zero address
    function test_set_multi_message_caller_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        gac.setMultiMessageCaller(address(0));
    }

    /// @dev sets multi message receiver
    function test_set_multi_message_receiver() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(gac));
        emit MultiMessageReceiverUpdated(DST_CHAIN_ID, address(42));

        gac.setMultiMessageReceiver(DST_CHAIN_ID, address(42));

        assertEq(gac.getMultiMessageReceiver(DST_CHAIN_ID), address(42));
    }

    /// @dev only owner can set multi message receiver
    function test_set_multi_message_receiver_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        gac.setMultiMessageReceiver(DST_CHAIN_ID, address(42));
    }

    /// @dev cannot set multi message receiver to zero address
    function test_set_multi_message_receiver_zero_address() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        gac.setMultiMessageReceiver(DST_CHAIN_ID, address(0));
    }

    /// @dev cannot set multi message receiver on zero chain ID
    function test_set_multi_message_receiver_zero_chain_id() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        gac.setMultiMessageReceiver(0, address(42));
    }

    /// @dev sets global message delivery gas limit
    function test_set_global_msg_delivery_gas_limit() public {
        vm.startPrank(owner);

        uint256 oldLimit = gac.getGlobalMsgDeliveryGasLimit();
        vm.expectEmit(true, true, true, true, address(gac));
        emit DstGasLimitUpdated(oldLimit, 420000);

        gac.setGlobalMsgDeliveryGasLimit(420000);

        assertEq(gac.getGlobalMsgDeliveryGasLimit(), 420000);
    }

    /// @dev only owner can set global message delivery gas limit
    function test_set_global_msg_delivery_gas_limit_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert("Ownable: caller is not the owner");
        gac.setGlobalMsgDeliveryGasLimit(420000);
    }

    /// @dev cannot set a gas limit lower than the minimum
    function test_set_global_msg_delivery_gas_limit_lower_than_min() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.INVALID_DST_GAS_LIMIT_MIN.selector);
        gac.setGlobalMsgDeliveryGasLimit(30000);
    }

    /// @dev checks if address is the global owner
    function test_is_global_owner() public {
        assertTrue(gac.isGlobalOwner(owner));
        assertFalse(gac.isGlobalOwner(caller));
    }

    /// @dev gets the global owner
    function test_get_global_owner() public {
        assertEq(gac.getGlobalOwner(), owner);
    }
}
