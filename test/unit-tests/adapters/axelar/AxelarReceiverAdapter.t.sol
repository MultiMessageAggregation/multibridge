// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../../../Setup.t.sol";
import "../../../contracts-mock/adapters/axelar/MockAxelarGateway.sol";
import "src/adapters/axelar/libraries/StringAddressConversion.sol";
import "src/MultiMessageReceiver.sol";
import "src/interfaces/EIP5164/MessageExecutor.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import "src/libraries/Types.sol";
import {AxelarReceiverAdapter} from "src/adapters/axelar/AxelarReceiverAdapter.sol";

contract AxelarReceiverAdapterTest is Setup {
    using StringAddressConversion for address;

    event MessageIdExecuted(uint256 indexed fromChainId, bytes32 indexed messageId);
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter, bytes senderChain);

    uint256 constant SRC_CHAIN_ID = 1;
    uint256 constant DST_CHAIN_ID = 137;

    AxelarReceiverAdapter adapter;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        adapter = AxelarReceiverAdapter(contractAddress[DST_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(adapter.gateway()), POLYGON_GATEWAY);
        assertEq(address(adapter.gac()), contractAddress[DST_CHAIN_ID]["GAC"]);
    }

    /// @dev gets the name
    function test_name() public {
        assertEq(adapter.name(), "axelar");
    }

    /// @dev updates sender adapter
    function test_update_sender_adapter() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit SenderAdapterUpdated(
            contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"], address(42), abi.encode("ethereum")
        );

        adapter.updateSenderAdapter(abi.encode("ethereum"), address(42));

        assertEq(adapter.senderAdapter(), address(42));
        assertEq(adapter.senderChain(), "ethereum");
    }

    /// @dev only privileged caller can update sender adapter
    function test_update_sender_adapter_only_privileged_caller() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_PRIVILEGED_CALLER.selector);
        adapter.updateSenderAdapter(abi.encode("ethereum"), address(42));
    }

    /// @dev cannot update sender adapter with zero chain ID
    function test_update_sender_adapter_zero_chain_id() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        adapter.updateSenderAdapter(abi.encode(""), address(42));
    }

    /// @dev cannot update sender adapter with zero address
    function test_update_sender_adapter_zero_address_input() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        adapter.updateSenderAdapter(abi.encode("ethereum"), address(0));
    }

    /// @dev executes message
    function test_execute() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
        new AxelarReceiverAdapter(address(new MockAxelarGateway(true /* validate */)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        // change receiver adapter on dst chain to the dummy one
        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectEmit(true, true, true, true, address(dummyAdapter));
        emit MessageIdExecuted(SRC_CHAIN_ID, msgId);

        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));

        assertTrue(dummyAdapter.isMessageExecuted(msgId));
        assertTrue(dummyAdapter.commandIdStatus(bytes32("commandId")));
    }

    /// @dev cannot execute message with invalid sender chain ID
    function test_execute_invalid_sender_chain_id() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
            new AxelarReceiverAdapter(address(new MockAxelarGateway(true)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        dummyAdapter.execute(bytes32("commandId"), "bsc", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message that is not approved by the Axelar gateway
    function test_execute_not_approved_by_gateway() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
            new AxelarReceiverAdapter(address(new MockAxelarGateway(false)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.NOT_APPROVED_BY_GATEWAY.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message with invalid sender adapter
    function test_execute_invalid_sender_adapter() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
            new AxelarReceiverAdapter(address(new MockAxelarGateway(true)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_SENDER_ADAPTER.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", address(44).toString(), abi.encode(payload));
    }

    /// @dev cannot execute message that is already executed
    function test_execute_message_id_already_executed() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
            new AxelarReceiverAdapter(address(new MockAxelarGateway(true)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));

        vm.expectRevert(abi.encodeWithSelector(MessageExecutor.MessageIdAlreadyExecuted.selector, msgId));
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message with invalid final destination
    function test_execute_invalid_final_destination() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
            new AxelarReceiverAdapter(address(new MockAxelarGateway(true)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: address(44),
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_FINAL_DESTINATION.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev reverts if message fails to be received
    function test_execute_message_failure() public {
        vm.startPrank(owner);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        AxelarReceiverAdapter dummyAdapter =
            new AxelarReceiverAdapter(address(new MockAxelarGateway(true)), contractAddress[DST_CHAIN_ID]["GAC"]);
        dummyAdapter.updateSenderAdapter(abi.encode("ethereum"), senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiMessageReceiver(receiverAddr).updateReceiverAdapter(receiverAdapters, operations);

        vm.startPrank(caller);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(0), // invalid target
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        // NOTE: Forge mangles low level error and doesn't allow checking for partial signature match
        vm.expectRevert();
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }
}
