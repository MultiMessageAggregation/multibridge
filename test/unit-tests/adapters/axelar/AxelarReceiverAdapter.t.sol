// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../../../Setup.t.sol";
import "../../../contracts-mock/adapters/axelar/MockAxelarGateway.sol";
import "src/adapters/axelar/libraries/StringAddressConversion.sol";
import "src/MultiBridgeMessageReceiver.sol";
import "src/interfaces/EIP5164/MessageExecutor.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import "src/libraries/Types.sol";
import {AxelarReceiverAdapter} from "src/adapters/axelar/AxelarReceiverAdapter.sol";

contract AxelarReceiverAdapterTest is Setup {
    using MessageLibrary for MessageLibrary.Message;
    using StringAddressConversion for address;

    event MessageIdExecuted(uint256 indexed fromChainId, bytes32 indexed messageId);
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter);

    AxelarReceiverAdapter adapter;
    address currOwner;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        adapter = AxelarReceiverAdapter(contractAddress[DST_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"]);
        currOwner = GAC(contractAddress[DST_CHAIN_ID]["GAC"]).owner();
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(adapter.gateway()), POLYGON_GATEWAY);
        assertEq(address(adapter.receiverGAC()), contractAddress[DST_CHAIN_ID]["GAC"]);
        assertEq(adapter.senderChainId(), "ethereum");
    }

    /// @dev constructor with invalid parameters should fail
    function test_constructor_zero_gateway_address() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new AxelarReceiverAdapter(address(0), "", address(42));
    }

    /// @dev constructor with invalid parameters should fail
    function test_constructor_zero_gac_address() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new AxelarReceiverAdapter(address(32), "", address(0));
    }

    /// @dev constructor cannot be called with zero chain id
    function test_constructor_zero_chain_id() public {
        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        new AxelarReceiverAdapter(address(42), "", address(42));
    }

    /// @dev gets the name
    function test_name() public {
        assertEq(adapter.name(), "AXELAR");
    }

    /// @dev updates sender adapter
    function test_update_sender_adapter() public {
        vm.startPrank(currOwner);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit SenderAdapterUpdated(contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"], address(42));

        adapter.updateSenderAdapter(address(42));

        assertEq(adapter.senderAdapter(), address(42));
    }

    /// @dev only global owner can update sender adapter
    function test_update_sender_adapter_only_global_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        adapter.updateSenderAdapter(address(42));
    }

    /// @dev cannot update sender adapter with zero address
    function test_update_sender_adapter_zero_address_input() public {
        vm.startPrank(currOwner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        adapter.updateSenderAdapter(address(0));
    }

    /// @dev executes message
    function test_execute() public {
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter, address receiverAddr) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
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
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter, address receiverAddr) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        dummyAdapter.execute(bytes32("commandId"), "bsc", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message that is not approved by the Axelar gateway
    function test_execute_not_approved_by_gateway() public {
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter, address receiverAddr) = _prepareDummyAdapter(false);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.NOT_APPROVED_BY_GATEWAY.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message with invalid sender adapter
    function test_execute_invalid_sender_adapter() public {
        (AxelarReceiverAdapter dummyAdapter,, address receiverAddr) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_SENDER_ADAPTER.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", address(43).toString(), abi.encode(payload));
    }

    /// @dev cannot execute message that is already executed
    function test_execute_message_id_already_executed() public {
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter, address receiverAddr) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));

        vm.expectRevert(abi.encodeWithSelector(MessageExecutor.MessageIdAlreadyExecuted.selector, msgId));
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message with invalid receiver adapter
    function test_execute_invalid_receiver_adapter() public {
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter,) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(43),
            finalDestination: address(44),
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_RECEIVER_ADAPTER.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev cannot execute message with invalid final destination
    function test_execute_invalid_final_destination() public {
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter,) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
            finalDestination: address(43),
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_FINAL_DESTINATION.selector);
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    /// @dev reverts if message fails to be received
    function test_execute_message_failure() public {
        (AxelarReceiverAdapter dummyAdapter, address senderAdapter, address receiverAddr) = _prepareDummyAdapter(true);

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(0), // invalid target
            nonce: 0,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: type(uint256).max
        });
        bytes32 msgId = message.computeMsgId();

        AdapterPayload memory payload = AdapterPayload({
            msgId: msgId,
            senderAdapterCaller: address(42),
            receiverAdapter: address(dummyAdapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                MessageExecutor.MessageFailure.selector, msgId, abi.encodePacked(Error.INVALID_TARGET.selector)
            )
        );
        dummyAdapter.execute(bytes32("commandId"), "ethereum", senderAdapter.toString(), abi.encode(payload));
    }

    function _prepareDummyAdapter(bool _validateCall)
        internal
        returns (AxelarReceiverAdapter dummyAdapter, address senderAdapter, address receiverAddr)
    {
        vm.startPrank(currOwner);

        senderAdapter = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];
        dummyAdapter = new AxelarReceiverAdapter(
            address(new MockAxelarGateway(_validateCall)), "ethereum", contractAddress[DST_CHAIN_ID]["GAC"]
        );
        dummyAdapter.updateSenderAdapter(senderAdapter);

        vm.startPrank(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        address[] memory receiverAdapters = new address[](1);
        receiverAdapters[0] = address(dummyAdapter);
        bool[] memory operations = new bool[](1);
        operations[0] = true;
        MultiBridgeMessageReceiver(receiverAddr).updateReceiverAdapters(receiverAdapters, operations);

        vm.startPrank(caller);
    }
}
