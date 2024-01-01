// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";
import "src/adapters/wormhole/WormholeReceiverAdapter.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import {MultiBridgeMessageReceiver} from "src/MultiBridgeMessageReceiver.sol";
import {IMultiBridgeMessageReceiver} from "src/interfaces/IMultiBridgeMessageReceiver.sol";

contract MultiBridgeMessageReceiverTest is Setup {
    using MessageLibrary for MessageLibrary.Message;

    event BridgeReceiverAdapterUpdated(address indexed receiverAdapter, bool add);
    event QuorumUpdated(uint64 oldValue, uint64 newValue);
    event GovernanceTimelockUpdated(address oldTimelock, address newTimelock);
    event BridgeMessageReceived(
        bytes32 indexed msgId, string indexed bridgeName, uint256 nonce, address receiverAdapter
    );
    event MessageExecutionScheduled(
        bytes32 indexed msgId, address indexed target, uint256 nativeValue, uint256 nonce, bytes callData
    );

    MultiBridgeMessageReceiver receiver;
    address axelarAdapterAddr;
    address wormholeAdapterAddr;
    address timelockAddr;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        receiver = MultiBridgeMessageReceiver(contractAddress[DST_CHAIN_ID][bytes("MMA_RECEIVER")]);
        axelarAdapterAddr = contractAddress[DST_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"];
        wormholeAdapterAddr = contractAddress[DST_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"];
        timelockAddr = contractAddress[DST_CHAIN_ID]["TIMELOCK"];
    }

    /// @dev verifies default setup
    function test_constructor() public {
        assertEq(receiver.srcChainId(), SRC_CHAIN_ID);
        assertEq(address(receiver.gac()), contractAddress[DST_CHAIN_ID]["GAC"]);
        assertEq(receiver.quorum(), 2);
        assertTrue(receiver.isTrustedExecutor(wormholeAdapterAddr));
        assertTrue(receiver.isTrustedExecutor(axelarAdapterAddr));
    }

    /// @dev cannot be called with zero source chain id
    function test_constructor_zero_chain_id_input() public {
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(43);

        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        new MultiBridgeMessageReceiver(0, address(42), receiverAdapters, 1);
    }

    /// @dev cannot be called with zero address GAC
    function test_constructor_zero_gac_address_input() public {
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(43);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new MultiBridgeMessageReceiver(SRC_CHAIN_ID, address(0), receiverAdapters, 1);
    }

    /// @dev cannot be called with receiver adapters containing zero address
    function test_constructor_zero_address_adapter() public {
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(0);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new MultiBridgeMessageReceiver(SRC_CHAIN_ID, address(42), receiverAdapters, 1);
    }

    /// @dev cannot be called with zero quorum
    function test_constructor_zero_quorum() public {
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(42);

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        new MultiBridgeMessageReceiver(SRC_CHAIN_ID, address(43), receiverAdapters, 0);
    }

    /// @dev cannot be called with quorum too large
    function test_constructor_quorum_too_large() public {
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(42);

        vm.expectRevert(Error.INVALID_QUORUM_THRESHOLD.selector);
        new MultiBridgeMessageReceiver(SRC_CHAIN_ID, address(43), receiverAdapters, 2);
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
        bytes32 msgId = message.computeMsgId();

        vm.expectEmit(true, true, true, true, address(receiver));
        emit BridgeMessageReceived(msgId, "WORMHOLE", 42, wormholeAdapterAddr);

        receiver.receiveMessage(message);

        assertFalse(receiver.isExecutionScheduled(msgId));

        assertTrue(receiver.msgDeliveries(msgId, wormholeAdapterAddr));

        assertEq(receiver.msgDeliveryCount(msgId), 1);

        assertEq(receiver.msgExecParamsHash(msgId), message.computeExecutionParamsHash());
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        vm.startPrank(axelarAdapterAddr);
        receiver.receiveMessage(message);

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
            })
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
            })
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
            })
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
            })
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

        receiver.receiveMessage(message);

        vm.expectRevert(Error.DUPLICATE_MESSAGE_DELIVERY_BY_ADAPTER.selector);
        receiver.receiveMessage(message);
    }

    /// @dev scheduled message should be rejected
    function test_receiver_message_msg_id_already_scheduled() public {
        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        // Reduce quorum first
        vm.startPrank(address(timelockAddr));
        receiver.updateQuorum(1);

        vm.startPrank(wormholeAdapterAddr);
        receiver.receiveMessage(message);

        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());

        vm.startPrank(axelarAdapterAddr);
        vm.expectRevert(Error.MSG_ID_ALREADY_SCHEDULED.selector);
        receiver.receiveMessage(message);
    }

    /// @dev schedules message delivered by two adapters
    function test_schedule_message_execution() public {
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        vm.startPrank(axelarAdapterAddr);
        receiver.receiveMessage(message);

        vm.expectEmit(true, true, true, true, address(receiver));
        emit MessageExecutionScheduled(msgId, address(42), 0, 42, bytes("42"));

        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());
        assertTrue(receiver.isExecutionScheduled(msgId));
    }

    /// @dev cannot execute mismatched message params and hash
    function test_schedule_message_hash_mismatch() public {
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        message.nonce = 43;
        vm.expectRevert(Error.EXEC_PARAMS_HASH_MISMATCH.selector);
        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());
    }

    /// @dev cannot schedule execution of message past deadline
    function test_schedule_message_execution_passed_deadline() public {
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        vm.expectRevert(Error.MSG_EXECUTION_PASSED_DEADLINE.selector);
        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());
    }

    /// @dev cannot schedule execution of message that has already been scheduled
    function test_schedule_message_execution_already_scheduled() public {
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        vm.startPrank(axelarAdapterAddr);
        receiver.receiveMessage(message);

        receiver.scheduleMessageExecution(
            msgId,
            MessageLibrary.MessageExecutionParams({
                target: message.target,
                callData: message.callData,
                value: message.nativeValue,
                nonce: message.nonce,
                expiration: message.expiration
            })
        );

        vm.expectRevert(Error.MSG_ID_ALREADY_SCHEDULED.selector);
        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());
    }

    /// @dev cannot schedule message execution without quorum
    function test_schedule_message_execution_quorum_not_met() public {
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        vm.expectRevert(Error.QUORUM_NOT_ACHIEVED.selector);
        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());
    }

    /// @dev updates governance timelock
    function test_update_governance_timelock() public {
        vm.startPrank(timelockAddr);

        vm.expectEmit(true, true, true, true, address(receiver));
        emit GovernanceTimelockUpdated(receiver.governanceTimelock(), address(42));

        receiver.updateGovernanceTimelock(address(42));
        assertEq(receiver.governanceTimelock(), address(42));
    }

    /// @dev cannot update governance timelock with zero address
    function test_update_governance_timelock_zero_address() public {
        vm.startPrank(timelockAddr);

        vm.expectRevert(Error.ZERO_GOVERNANCE_TIMELOCK.selector);
        receiver.updateGovernanceTimelock(address(0));
    }

    /// @dev adds one receiver adapter
    function test_update_receiver_adapter_add() public {
        vm.startPrank(timelockAddr);

        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = address(42);
        bool[] memory operations = new bool[](1);
        operations[0] = true;

        assertFalse(receiver.isTrustedExecutor(address(42)));

        vm.expectEmit(true, true, true, true, address(receiver));
        emit BridgeReceiverAdapterUpdated(address(42), true);
        receiver.updateReceiverAdapters(updatedAdapters, operations);

        assertTrue(receiver.isTrustedExecutor(wormholeAdapterAddr));
        assertTrue(receiver.isTrustedExecutor(axelarAdapterAddr));
        assertTrue(receiver.isTrustedExecutor(address(42)));
    }

    /// @dev adding a receiver adapter that already exists should fail
    function test_update_receiver_adapter_add_existing() public {
        vm.startPrank(timelockAddr);

        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = wormholeAdapterAddr;
        bool[] memory operations = new bool[](1);
        operations[0] = true;

        vm.expectRevert(abi.encodeWithSelector(Error.UPDATE_RECEIVER_ADAPTER_FAILED.selector, "adapter already added"));
        receiver.updateReceiverAdapters(updatedAdapters, operations);
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
        emit BridgeReceiverAdapterUpdated(wormholeAdapterAddr, false);

        receiver.updateReceiverAdapters(updatedAdapters, operations);
        assertFalse(receiver.isTrustedExecutor(wormholeAdapterAddr));
        assertTrue(receiver.isTrustedExecutor(axelarAdapterAddr));
    }

    /// @dev removing a receiver adapter that does not exist should fail
    function test_update_receiver_adapter_remove_non_existing() public {
        vm.startPrank(timelockAddr);

        address[] memory updatedAdapters = new address[](1);
        updatedAdapters[0] = address(42);
        bool[] memory operations = new bool[](1);
        operations[0] = false;

        assertFalse(receiver.isTrustedExecutor(address(42)));

        vm.expectRevert(abi.encodeWithSelector(Error.UPDATE_RECEIVER_ADAPTER_FAILED.selector, "adapter not found"));
        receiver.updateReceiverAdapters(updatedAdapters, operations);
    }

    /// @dev only governance timelock can call
    function test_update_receiver_adapter_only_governance_timelock() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
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

    /// @dev cannot update with empty adapters list
    function test_update_receiver_adapter_empty_lst() public {
        vm.startPrank(timelockAddr);

        vm.expectRevert(Error.ZERO_RECEIVER_ADAPTER.selector);

        receiver.updateReceiverAdapters(new address[](0), new bool[](0));
    }

    /// @dev cannot update with zero adapter address
    function test_update_receiver_adapter_zero_address() public {
        vm.startPrank(timelockAddr);

        address[] memory adapters = new address[](1);
        adapters[0] = address(0);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);

        receiver.updateReceiverAdapters(adapters, new bool[](1));
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

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
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
        receiver.updateReceiverAdaptersAndQuorum(adapters, new bool[](1), newQuorum);

        /// @dev asserts the quorum and adapter lengths
        assertEq(receiver.quorum(), newQuorum);
        assertEq(receiver.isTrustedExecutor(adapters[0]), false);
    }

    /// @dev valid quorum and receiver updater in one single call, adding adapters and increasing quorum
    function test_quorum_and_receiver_updater_add_increase() public {
        vm.startPrank(timelockAddr);

        // First, add one adapter
        address[] memory addOneAdapter = new address[](1);
        addOneAdapter[0] = address(42);
        bool[] memory addOneOps = new bool[](1);
        addOneOps[0] = true;

        // Add two more and update quorum to 4
        address[] memory addTwoAdapters = new address[](2);
        addTwoAdapters[0] = address(420);
        addTwoAdapters[1] = address(421);

        bool[] memory addTwoOps = new bool[](2);
        addTwoOps[0] = true;
        addTwoOps[1] = true;

        uint64 newQuorum = 4;

        receiver.updateReceiverAdaptersAndQuorum(addTwoAdapters, addTwoOps, newQuorum);

        /// @dev asserts the quorum and adapter lengths
        assertEq(receiver.quorum(), newQuorum);
        assertEq(receiver.isTrustedExecutor(addTwoAdapters[0]), true);
        assertEq(receiver.isTrustedExecutor(addTwoAdapters[1]), true);
    }

    /// @dev valid quorum and receiver updater in one single call, removing adapter and decreasing quorum
    function test_quorum_and_receiver_updater_remove_decrease() public {
        vm.startPrank(timelockAddr);

        // Remove one adapter and update quorum to 1
        address[] memory removeOneAdapter = new address[](1);
        removeOneAdapter[0] = axelarAdapterAddr;

        uint64 newQuorum = 1;

        receiver.updateReceiverAdaptersAndQuorum(removeOneAdapter, new bool[](1), newQuorum);

        /// @dev asserts the quorum and adapter lengths
        assertEq(receiver.quorum(), newQuorum);
        assertEq(receiver.isTrustedExecutor(wormholeAdapterAddr), true);
        assertEq(receiver.isTrustedExecutor(axelarAdapterAddr), false);
    }

    /// @dev valid quorum and receiver updater in one single call, removing one, adding two and increasing quorum
    function test_quorum_and_receiver_updater_remove_add_increase() public {
        vm.startPrank(timelockAddr);

        // Remove one adapter and update quorum to 1
        address[] memory removeAddAdapters = new address[](3);
        removeAddAdapters[0] = axelarAdapterAddr;
        removeAddAdapters[1] = address(42);
        removeAddAdapters[2] = address(43);
        bool[] memory removeAddOps = new bool[](3);
        removeAddOps[0] = false;
        removeAddOps[1] = true;
        removeAddOps[2] = true;

        uint64 newQuorum = 3;

        receiver.updateReceiverAdaptersAndQuorum(removeAddAdapters, removeAddOps, newQuorum);

        /// @dev asserts the quorum and adapter lengths
        assertEq(receiver.quorum(), newQuorum);
        assertEq(receiver.isTrustedExecutor(wormholeAdapterAddr), true);
        assertEq(receiver.isTrustedExecutor(axelarAdapterAddr), false);
        assertEq(receiver.isTrustedExecutor(removeAddAdapters[1]), true);
        assertEq(receiver.isTrustedExecutor(removeAddAdapters[2]), true);
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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        (bool isScheduled, uint256 msgCurrentVotes, string[] memory successfulBridge) = receiver.getMessageInfo(msgId);
        assertFalse(isScheduled);
        assertEq(msgCurrentVotes, 1);
        assertEq(successfulBridge.length, 1);
        assertEq(successfulBridge[0], WormholeReceiverAdapter(wormholeAdapterAddr).name());
    }

    /// @dev should get message info for invalid message id
    function test_get_message_info_invalid_message_id() public {
        (bool isScheduled, uint256 msgCurrentVotes, string[] memory successfulBridge) =
            receiver.getMessageInfo(bytes32(0));
        assertFalse(isScheduled);
        assertEq(msgCurrentVotes, 0);
        assertEq(successfulBridge.length, 0);
    }

    /// @dev should get message info for partial delivery
    function test_get_message_info_partial_delivery() public {
        vm.startPrank(wormholeAdapterAddr);

        // Assuming there's a function to add executors or that multiple executors exist by default

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 42,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);

        // You may need a mechanism to simulate or enforce failed deliveries for certain executors

        (bool isScheduled, uint256 msgCurrentVotes, string[] memory successfulBridge) = receiver.getMessageInfo(msgId);
        assertFalse(isScheduled);
        // Adjust the following assertions as needed based on your setup
        assertTrue(msgCurrentVotes > 0); // Ensure there's at least one successful delivery
        assertEq(successfulBridge.length, msgCurrentVotes);
    }

    /// @dev should get message info scheduled for execution
    function test_get_message_info_scheduled_execution() public {
        // Reduce quorum first
        vm.startPrank(address(timelockAddr));
        receiver.updateQuorum(1);
        vm.stopPrank();

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
        bytes32 msgId = message.computeMsgId();

        receiver.receiveMessage(message);
        receiver.scheduleMessageExecution(msgId, message.extractExecutionParams());

        (bool isScheduled, uint256 msgCurrentVotes, string[] memory successfulBridge) = receiver.getMessageInfo(msgId);
        assertTrue(isScheduled);
        assertEq(msgCurrentVotes, 1);
        assertEq(successfulBridge.length, 1);
    }
}
