// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";
import "test/contracts-mock/FailingSenderAdapter.sol";
import "test/contracts-mock/ZeroAddressReceiverGac.sol";
import "src/interfaces/IBridgeSenderAdapter.sol";
import "src/interfaces/IMultiMessageReceiver.sol";
import "src/interfaces/IGAC.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import {MultiMessageSender} from "src/MultiMessageSender.sol";

contract MultiMessageSenderTest is Setup {
    event MultiMessageMsgSent(
        bytes32 indexed msgId,
        uint256 nonce,
        uint256 indexed dstChainId,
        address indexed target,
        bytes callData,
        uint256 nativeValue,
        uint256 expiration,
        address[] senderAdapters,
        bool[] adapterSuccess
    );
    event SenderAdapterUpdated(address senderAdapter, bool add);
    event ErrorSendMessage(address senderAdapter, MessageLibrary.Message message);

    uint256 constant SRC_CHAIN_ID = 1;
    uint256 constant DST_CHAIN_ID = 137;

    MultiMessageSender sender;
    address receiver;
    IGAC gac;
    address wormholeAdapterAddr;
    address axelarAdapterAddr;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        sender = MultiMessageSender(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]);
        receiver = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        gac = IGAC(contractAddress[SRC_CHAIN_ID]["GAC"]);
        wormholeAdapterAddr = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
        axelarAdapterAddr = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(sender.gac()), contractAddress[SRC_CHAIN_ID]["GAC"]);
    }

    /// @dev cannot be called with zero address GAC
    function test_constructor_zero_address_input() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new MultiMessageSender(address(0));
    }

    /// @dev perform remote call
    function test_remote_call() public {
        vm.startPrank(caller);

        address[] memory senderAdapters = new address[](2);
        senderAdapters[0] = wormholeAdapterAddr;
        senderAdapters[1] = axelarAdapterAddr;

        bool[] memory adapterSuccess = new bool[](2);
        adapterSuccess[0] = true;
        adapterSuccess[1] = true;

        uint256 expiration = block.timestamp + EXPIRATION_CONSTANT;

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 1,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: expiration
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        uint256 fee = sender.estimateTotalMessageFee(DST_CHAIN_ID, receiver, address(42), bytes("42"), 0);

        vm.expectEmit(true, true, true, true, address(sender));
        emit MultiMessageMsgSent(
            msgId, 1, DST_CHAIN_ID, address(42), bytes("42"), 0, expiration, senderAdapters, adapterSuccess
        );

        sender.remoteCall{value: fee}(DST_CHAIN_ID, address(42), bytes("42"), 0, expiration);

        assertEq(sender.nonce(), 1);
    }

    /// @dev perform remote call, checking for refund
    function test_remote_call_refund() public {
        vm.startPrank(caller);

        uint256 expiration = block.timestamp + EXPIRATION_CONSTANT;
        uint256 nativeValue = 2 ether;

        uint256 balanceBefore = gac.getRefundAddress().balance;
        sender.remoteCall{value: nativeValue}(DST_CHAIN_ID, address(42), bytes("42"), 0, expiration);

        uint256 balanceAfter = gac.getRefundAddress().balance;
        uint256 fee = sender.estimateTotalMessageFee(DST_CHAIN_ID, receiver, address(42), bytes("42"), 0);
        assertEq(balanceAfter - balanceBefore, nativeValue - fee);
    }

    /// @dev perform remote call with an excluded adapter
    function test_remote_call_excluded_adapter() public {
        vm.startPrank(caller);

        address[] memory senderAdapters = new address[](1);
        senderAdapters[0] = wormholeAdapterAddr;

        bool[] memory adapterSuccess = new bool[](1);
        adapterSuccess[0] = true;

        address[] memory excludedAdapters = new address[](1);
        excludedAdapters[0] = axelarAdapterAddr;

        uint256 expiration = block.timestamp + EXPIRATION_CONSTANT;

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 1,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: expiration
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        uint256 fee =
            IBridgeSenderAdapter(wormholeAdapterAddr).getMessageFee(DST_CHAIN_ID, receiver, abi.encode(message));

        vm.expectEmit(true, true, true, true, address(sender));
        emit MultiMessageMsgSent(
            msgId, 1, DST_CHAIN_ID, address(42), bytes("42"), 0, expiration, senderAdapters, adapterSuccess
        );

        sender.remoteCall{value: fee}(DST_CHAIN_ID, address(42), bytes("42"), 0, expiration, excludedAdapters);
    }

    /// @dev only caller can perform remote call
    function test_remote_call_only_caller() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.INVALID_PRIVILEGED_CALLER.selector);
        sender.remoteCall(DST_CHAIN_ID, address(42), bytes("42"), 0, block.timestamp + EXPIRATION_CONSTANT);
    }

    /// @dev cannot call with dst chain ID of 0
    function test_remote_call_zero_chain_id() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        sender.remoteCall(0, address(42), bytes("42"), 0, block.timestamp + EXPIRATION_CONSTANT);
    }

    /// @dev cannot call with target address of 0
    function test_remote_call_zero_target_address() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_TARGET.selector);
        sender.remoteCall(DST_CHAIN_ID, address(0), bytes("42"), 0, block.timestamp + EXPIRATION_CONSTANT);
    }

    /// @dev cannot call with receiver address of 0
    function test_remote_call_zero_receiver_address() public {
        vm.startPrank(caller);

        MultiMessageSender dummySender = new MultiMessageSender(address(new ZeroAddressReceiverGac(caller)));

        vm.expectRevert(Error.ZERO_RECEIVER_ADAPTER.selector);
        dummySender.remoteCall(DST_CHAIN_ID, address(42), bytes("42"), 0, block.timestamp + EXPIRATION_CONSTANT);
    }

    /// @dev cannot call with no sender adapter
    function test_remote_call_no_sender_adapter_found() public {
        vm.startPrank(owner);

        // Remove both adapters
        address[] memory senderAdapters = new address[](2);
        senderAdapters[0] = wormholeAdapterAddr;
        senderAdapters[1] = axelarAdapterAddr;

        sender.removeSenderAdapters(senderAdapters);

        vm.startPrank(caller);

        vm.expectRevert(Error.NO_SENDER_ADAPTER_FOUND.selector);
        sender.remoteCall(DST_CHAIN_ID, address(42), bytes("42"), 0, block.timestamp + EXPIRATION_CONSTANT);
    }

    /// @dev should proceed with the call despite one failing adapter, emitting an error message
    function test_remote_call_failing_adapter() public {
        vm.startPrank(owner);

        // Add failing adapter
        address[] memory addedSenderAdapters = new address[](1);
        address failingAdapterAddr = address(new FailingSenderAdapter());
        addedSenderAdapters[0] = failingAdapterAddr;
        sender.addSenderAdapters(addedSenderAdapters);

        vm.startPrank(caller);

        address[] memory senderAdapters = new address[](3);
        senderAdapters[0] = wormholeAdapterAddr;
        senderAdapters[1] = axelarAdapterAddr;
        senderAdapters[2] = failingAdapterAddr;

        bool[] memory adapterSuccess = new bool[](3);
        adapterSuccess[0] = true;
        adapterSuccess[1] = true;
        adapterSuccess[2] = false;

        uint256 expiration = block.timestamp + EXPIRATION_CONSTANT;

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 1,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: expiration
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        uint256 fee = sender.estimateTotalMessageFee(DST_CHAIN_ID, receiver, address(42), bytes("42"), 0);

        vm.expectEmit(true, true, true, true, address(sender));
        emit ErrorSendMessage(failingAdapterAddr, message);

        vm.expectEmit(true, true, true, true, address(sender));
        emit MultiMessageMsgSent(
            msgId, 1, DST_CHAIN_ID, address(42), bytes("42"), 0, expiration, senderAdapters, adapterSuccess
        );

        sender.remoteCall{value: fee}(DST_CHAIN_ID, address(42), bytes("42"), 0, expiration);
    }

    /// @dev adds two sender adapters
    function test_add_sender_adapters() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](2);
        adapters[0] = address(42);
        adapters[1] = address(43);

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdapterUpdated(address(42), true);
        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdapterUpdated(address(43), true);

        sender.addSenderAdapters(adapters);

        assertEq(sender.senderAdapters(0), wormholeAdapterAddr);
        assertEq(sender.senderAdapters(1), axelarAdapterAddr);
        assertEq(sender.senderAdapters(2), address(42));
        assertEq(sender.senderAdapters(3), address(43));
    }

    /// @dev only owner can call
    function test_add_sender_adapters_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        sender.addSenderAdapters(new address[](42));
    }

    /// @dev cannot add adapter with zero address
    function test_add_sender_adapters_zero_address_input() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](1);
        adapters[0] = address(0);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        sender.addSenderAdapters(adapters);
    }

    /// @dev cannot add duplicate adapters
    function test_add_sender_adapters_duplicate_new_adapter() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](2);
        adapters[0] = address(42);
        adapters[1] = address(42);

        vm.expectRevert(Error.DUPLICATE_SENDER_ADAPTER.selector);
        sender.addSenderAdapters(adapters);
    }

    /// @dev cannot add an existing adapter
    function test_add_sender_adapters_duplicate_existing_adapter() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](1);
        adapters[0] = wormholeAdapterAddr;

        vm.expectRevert(Error.DUPLICATE_SENDER_ADAPTER.selector);
        sender.addSenderAdapters(adapters);
    }

    /// @dev removes two sender adapters
    function test_remove_sender_adapters() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](2);
        adapters[0] = axelarAdapterAddr;
        adapters[1] = wormholeAdapterAddr;

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdapterUpdated(axelarAdapterAddr, false);
        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdapterUpdated(wormholeAdapterAddr, false);

        sender.removeSenderAdapters(adapters);

        vm.expectRevert();
        sender.senderAdapters(0);
    }

    /// @dev only owner can call
    function test_remove_sender_adapters_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        sender.removeSenderAdapters(new address[](0));
    }

    /// @dev tries to remove two nonexistent sender adapters, no-op
    function test_remove_sender_adapters_nonexistent() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](2);
        adapters[0] = address(42);
        adapters[1] = address(43);

        sender.removeSenderAdapters(adapters);

        assertEq(sender.senderAdapters(0), wormholeAdapterAddr);
        assertEq(sender.senderAdapters(1), axelarAdapterAddr);
    }

    /// @dev should estimate total message fee
    function test_estimate_total_message_fee() public {
        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });

        uint256 totalFee = sender.estimateTotalMessageFee(DST_CHAIN_ID, receiver, address(42), bytes("42"), 0);
        bytes memory data = abi.encodeWithSelector(IMultiMessageReceiver.receiveMessage.selector, message);

        uint256 expectedTotalFee;
        expectedTotalFee += IBridgeSenderAdapter(wormholeAdapterAddr).getMessageFee(DST_CHAIN_ID, receiver, data);
        expectedTotalFee += IBridgeSenderAdapter(axelarAdapterAddr).getMessageFee(DST_CHAIN_ID, receiver, data);

        assertEq(totalFee, expectedTotalFee);
    }
}
