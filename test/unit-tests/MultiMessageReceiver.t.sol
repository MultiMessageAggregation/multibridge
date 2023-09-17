// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";
import "src/adapters/wormhole/WormholeReceiverAdapter.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import {MultiMessageReceiver} from "src/MultiMessageReceiver.sol";

contract MultiMessageReceiverTest is Setup {
    event ReceiverAdapterUpdated(address indexed receiverAdapter, bool add);
    event QuorumUpdated(uint64 oldValue, uint64 newValue);
    event SingleBridgeMsgReceived(
        bytes32 indexed msgId, string indexed bridgeName, uint256 nonce, address receiverAdapter
    );
    event MessageExecuted(
        bytes32 indexed msgId, address indexed target, uint256 nativeValue, uint256 nonce, bytes callData
    );

    MultiMessageReceiver receiver;
    address wormholeAdapterAddr;
    address axelarAdapterAddr;
    address timelockAddr;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        receiver = MultiMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]);
        wormholeAdapterAddr = contractAddress[DST_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"];
        axelarAdapterAddr = contractAddress[DST_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"];
        timelockAddr = contractAddress[DST_CHAIN_ID]["TIMELOCK"];
    }

    /// @dev initializer
    function test_initialize() public {
        address[] memory adapters = new address[](2);
        adapters[0] = wormholeAdapterAddr;
        adapters[1] = axelarAdapterAddr;

        bool[] memory operation = new bool[](2);
        operation[0] = true;
        operation[1] = true;

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();
        dummyReceiver.initialize(adapters, operation, 2, timelockAddr);

        assertEq(dummyReceiver.quorum(), 2);
        assertEq(dummyReceiver.trustedExecutor(0), wormholeAdapterAddr);
        assertEq(dummyReceiver.trustedExecutor(1), axelarAdapterAddr);
    }

    /// @dev initializer cannot be called twice
    function test_initialize_initialized() public {
        vm.startPrank(caller);

        vm.expectRevert("Initializable: contract is already initialized");
        receiver.initialize(new address[](0), new bool[](0), 0, address(0));
    }

    /// @dev cannot be called with zero adapter
    function test_initialize_zero_receiver_adapter() public {
        vm.startPrank(caller);

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();

        vm.expectRevert(Error.ZERO_RECEIVER_ADAPTER.selector);
        dummyReceiver.initialize(new address[](0), new bool[](0), 0, address(0));
    }

    /// @dev cannot be called with zero address adapter
    function test_initialize_zero_address_input() public {
        vm.startPrank(caller);

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();
        address[] memory adapters = new address[](1);
        adapters[0] = address(0);

        bool[] memory operation = new bool[](1);
        operation[0] = true;

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        dummyReceiver.initialize(adapters, operation, 1, timelockAddr);
    }

    /// @dev quorum cannot be larger than the number of receiver adapters
    function test_initialize_quorum_too_large() public {
        vm.startPrank(caller);

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();
        address[] memory adapters = new address[](1);
        adapters[0] = address(42);

        bool[] memory operation = new bool[](1);
        operation[0] = true;

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        dummyReceiver.initialize(adapters, operation, 2, timelockAddr);
    }

    /// @dev quorum cannot be larger than the number of unique receiver adapters
    function test_initialize_quorum_larger_than_num_trusted_executors() public {
        vm.startPrank(caller);

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();
        address[] memory adapters = new address[](2);
        adapters[0] = address(42);
        adapters[1] = address(42);

        bool[] memory operation = new bool[](2);
        operation[0] = true;
        operation[1] = true;

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        dummyReceiver.initialize(adapters, operation, 2, timelockAddr);
    }

    /// @dev initializer quorum cannot be zero
    function test_initialize_zero_quorum() public {
        vm.startPrank(caller);

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();
        address[] memory adapters = new address[](1);
        adapters[0] = address(42);

        bool[] memory operation = new bool[](1);
        operation[0] = true;

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        dummyReceiver.initialize(adapters, operation, 0, timelockAddr);
    }

    /// @dev governance timelock cannot be zero address
    function test_initialize_zero_governance_timelock() public {
        vm.startPrank(caller);

        MultiMessageReceiver dummyReceiver = new MultiMessageReceiver();
        address[] memory adapters = new address[](1);
        adapters[0] = address(42);

        bool[] memory operation = new bool[](1);
        operation[0] = true;

        vm.expectRevert(Error.ZERO_GOVERNANCE_TIMELOCK.selector);
        dummyReceiver.initialize(adapters, operation, 1, address(0));
    }

    /// @dev receives message from one adapter
    function test_receive_message() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        vm.expectEmit(true, true, true, true, address(receiver));
        emit SingleBridgeMsgReceived(msgId, "WORMHOLE", 42, wormholeAdapterAddr);

        receiver.receiveMessage(message, "WORMHOLE");

        assertFalse(receiver.isExecuted(msgId));

        assertTrue(receiver.msgDeliveries(msgId, wormholeAdapterAddr));

        assertEq(receiver.msgDeliveryCount(msgId), 1);

        (address target, bytes memory callData, uint256 nativeValue, uint256 nonce, uint256 expiration) =
            receiver.msgExecData(msgId);
        assertEq(target, message.target);
        assertEq(callData, message.callData);
        assertEq(nativeValue, message.nativeValue);
        assertEq(nonce, message.nonce);
        assertEq(expiration, message.expiration);
    }

    /// @dev receives message from two adapters
    function test_receive_message_two_adapters() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        receiver.receiveMessage(message, "WORMHOLE");

        vm.startPrank(axelarAdapterAddr);
        receiver.receiveMessage(message, "AXELAR");

        assertEq(receiver.msgDeliveryCount(msgId), 2);
    }

    /// @dev only adapters can call
    function test_receive_message_only_receiver_adapter() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_RECEIVER_ADAPTER.selector);
        receiver.receiveMessage(
            MessageLibrary.Message({
                srcChainId: SRC_CHAIN_ID,
                dstChainId: DST_CHAIN_ID,
                target: address(0),
                nonce: 0,
                callData: bytes(""),
                nativeValue: 0,
                expiration: 0
            }),
            "WORMHOLE"
        );
    }

    /// @dev wrong dst chain
    function test_receive_message_invalid_dst_chain() public {
        vm.startPrank(wormholeAdapterAddr);

        vm.expectRevert(Error.INVALID_DST_CHAIN.selector);
        receiver.receiveMessage(
            MessageLibrary.Message({
                srcChainId: SRC_CHAIN_ID,
                dstChainId: BSC_CHAIN_ID,
                target: address(0),
                nonce: 0,
                callData: bytes(""),
                nativeValue: 0,
                expiration: 0
            }),
            "WORMHOLE"
        );
    }

    /// @dev target cannot be zero address
    function test_receive_message_invalid_target() public {
        vm.startPrank(wormholeAdapterAddr);

        vm.expectRevert(Error.INVALID_TARGET.selector);
        receiver.receiveMessage(
            MessageLibrary.Message({
                srcChainId: SRC_CHAIN_ID,
                dstChainId: DST_CHAIN_ID,
                target: address(0),
                nonce: 0,
                callData: bytes(""),
                nativeValue: 0,
                expiration: 0
            }),
            "WORMHOLE"
        );
    }

    /// @dev wrong src chain
    function test_receive_message_invalid_src_chain() public {
        vm.startPrank(wormholeAdapterAddr);

        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        receiver.receiveMessage(
            MessageLibrary.Message({
                srcChainId: BSC_CHAIN_ID,
                dstChainId: DST_CHAIN_ID,
                target: address(42),
                nonce: 0,
                callData: bytes(""),
                nativeValue: 0,
                expiration: 0
            }),
            "WORMHOLE"
        );
    }

    /// @dev duplicate message delivery should be rejected
    function test_receiver_message_duplicate_message_delivery_by_adapter() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });

        receiver.receiveMessage(message, "WORMHOLE");

        vm.expectRevert(Error.DUPLICATE_MESSAGE_DELIVERY_BY_ADAPTER.selector);
        receiver.receiveMessage(message, "WORMHOLE");
    }

    /// @dev executed message should be rejected
    function test_receiver_message_msg_id_already_executed() public {
        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        // Reduce quorum first
        vm.startPrank(address(timelockAddr));
        receiver.updateQuorum(1);

        vm.startPrank(wormholeAdapterAddr);
        receiver.receiveMessage(message, "WORMHOLE");

        receiver.executeMessage(msgId);

        vm.startPrank(axelarAdapterAddr);
        vm.expectRevert(Error.MSG_ID_ALREADY_EXECUTED.selector);
        receiver.receiveMessage(message, "AXELAR");
    }

    /// @dev executes message delivered by two adapters
    function test_execute_message() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        receiver.receiveMessage(message, "WORMHOLE");

        vm.startPrank(axelarAdapterAddr);
        receiver.receiveMessage(message, "AXELAR");

        vm.expectEmit(true, true, true, true, address(receiver));
        emit MessageExecuted(msgId, address(42), 0, 42, bytes("42"));

        receiver.executeMessage(msgId);

        assertTrue(receiver.isExecuted(msgId));
    }

    /// @dev cannot execute message past deadline
    function test_execute_message_passed_deadline() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: 0
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        receiver.receiveMessage(message, "WORMHOLE");

        vm.expectRevert(Error.MSG_EXECUTION_PASSED_DEADLINE.selector);
        receiver.executeMessage(msgId);
    }

    /// @dev cannot executed message that has already been executed
    function test_execute_message_msg_id_already_executed() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        receiver.receiveMessage(message, "WORMHOLE");

        vm.startPrank(axelarAdapterAddr);
        receiver.receiveMessage(message, "AXELAR");

        receiver.executeMessage(msgId);

        vm.expectRevert(Error.MSG_ID_ALREADY_EXECUTED.selector);
        receiver.executeMessage(msgId);
    }

    /// @dev cannot execute message without quorum
    function test_execute_message_quorum_not_met_for_exec() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        receiver.receiveMessage(message, "WORMHOLE");

        vm.expectRevert(Error.QUORUM_NOT_ACHIEVED.selector);
        receiver.executeMessage(msgId);
    }

    /// @dev adds one receiver adapter
    function test_update_receiver_adapter_add() public {
        vm.startPrank(timelockAddr);

        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = address(42);
        bool[] memory operations = new bool[](1);
        operations[0] = true;

        vm.expectEmit(true, true, true, true, address(receiver));
        emit ReceiverAdapterUpdated(address(42), true);

        receiver.updateReceiverAdapters(updatedAdapters, operations);

        assertEq(receiver.trustedExecutor(0), wormholeAdapterAddr);
        assertEq(receiver.trustedExecutor(1), axelarAdapterAddr);
        assertEq(receiver.trustedExecutor(2), address(42));
    }

    /// @dev removes one receiver adapter
    function test_update_receiver_adapter_remove() public {
        vm.startPrank(timelockAddr);

        // Reduce quorum first
        receiver.updateQuorum(1);

        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = wormholeAdapterAddr;
        bool[] memory operations = new bool[](1);
        operations[0] = false;

        vm.expectEmit(true, true, true, true, address(receiver));
        emit ReceiverAdapterUpdated(wormholeAdapterAddr, false);

        receiver.updateReceiverAdapters(updatedAdapters, operations);
        assertEq(receiver.trustedExecutor(0), axelarAdapterAddr);
    }

    /// @dev only governance timelock can call
    function test_update_receiver_adapter_only_governance_timelock() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_GOVERNANCE_TIMELOCK.selector);
        receiver.updateReceiverAdapters(new address[](0), new bool[](0));
    }

    /// @dev adapters and operations length mismatched
    function test_update_receiver_adapter_length_mismatched() public {
        vm.startPrank(timelockAddr);

        vm.expectRevert(Error.ARRAY_LENGTH_MISMATCHED.selector);
        address[] memory adapters = new address[](1);
        adapters[0] = address(420);

        bool[] memory operations = new bool[](2);

        receiver.updateReceiverAdapters(adapters, operations);
    }

    /// @dev cannot remove one receiver adapter without reducing quorum first
    function test_update_receiver_adapter_remove_invalid_quorum_threshold() public {
        vm.startPrank(timelockAddr);

        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = wormholeAdapterAddr;
        bool[] memory operations = new bool[](1);
        operations[0] = false;
        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        receiver.updateReceiverAdapters(updatedAdapters, operations);
    }

    /// @dev updates quorum
    function test_update_quorum() public {
        vm.startPrank(timelockAddr);

        // Add one adapter first
        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = address(42);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        receiver.updateReceiverAdapters(updatedAdapters, operations);

        vm.expectEmit(true, true, true, true, address(receiver));
        emit QuorumUpdated(2, 3);

        receiver.updateQuorum(3);
        assertEq(receiver.quorum(), 3);
    }

    /// @dev only governance timelock can call
    function test_update_quorum_only_governance_timelock() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_GOVERNANCE_TIMELOCK.selector);
        receiver.updateQuorum(0);
    }

    /// @dev quorum too large
    function test_update_quorum_too_large() public {
        vm.startPrank(timelockAddr);

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        receiver.updateQuorum(3);
    }

    /// @dev quorum of zero is invalid
    function test_update_quorum_zero() public {
        vm.startPrank(timelockAddr);

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        receiver.updateQuorum(0);
    }

    /// @dev valid quorum and receiver updater in one single call
    function test_quorum_and_receiver_updater() public {
        vm.startPrank(timelockAddr);

        address[] memory adapters = new address[](2);
        adapters[0] = address(420);
        adapters[1] = address(421);

        bool[] memory addOps = new bool[](2);
        addOps[0] = true;
        addOps[1] = true;

        /// @dev adds the adapters before removal
        receiver.updateReceiverAdapters(adapters, addOps);

        /// @dev asserts the quorum and adapter lengths
        assertEq(receiver.isTrustedExecutor(adapters[0]), true);
        assertEq(receiver.isTrustedExecutor(adapters[1]), true);

        adapters = new address[](1);
        adapters[0] = address(420);

        uint64 newQuorum = 1;

        /// @dev removes the newly updated adapter by reducing quorum by one
        receiver.updateQuorumAndReceiverAdapter(newQuorum, adapters, new bool[](1));

        /// @dev asserts the quorum and adapter lengths
        assertEq(receiver.quorum(), newQuorum);
        assertEq(receiver.isTrustedExecutor(adapters[0]), false);
    }

    /// @dev should get message info
    function test_get_message_info() public {
        vm.startPrank(wormholeAdapterAddr);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        receiver.receiveMessage(message, "WORMHOLE");

        (bool isExecuted, uint256 msgCurrentVotes, string[] memory successfulBridge) = receiver.getMessageInfo(msgId);
        assertFalse(isExecuted);
        assertEq(msgCurrentVotes, 1);
        assertEq(successfulBridge.length, 1);
        assertEq(successfulBridge[0], WormholeReceiverAdapter(wormholeAdapterAddr).name());
    }
}
