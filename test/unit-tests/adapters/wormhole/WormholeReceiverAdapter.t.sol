// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../../../Setup.t.sol";
import "src/MultiMessageReceiver.sol";
import "src/interfaces/EIP5164/MessageExecutor.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import "src/libraries/Types.sol";
import "src/libraries/TypeCasts.sol";
import {WormholeReceiverAdapter} from "src/adapters/wormhole/WormholeReceiverAdapter.sol";

contract WormholeReceiverAdapterTest is Setup {
    event MessageIdExecuted(uint256 indexed fromChainId, bytes32 indexed messageId);
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter);

    WormholeReceiverAdapter adapter;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        adapter = WormholeReceiverAdapter(contractAddress[DST_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(adapter.relayer()), POLYGON_RELAYER);
        assertEq(address(adapter.receiverGAC()), contractAddress[DST_CHAIN_ID]["GAC"]);
    }

    /// @dev constructor cannot be called with zero address relayer
    function test_constructor_zero_address_relayer() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new WormholeReceiverAdapter(address(0), address(42), _wormholeChainId(ETHEREUM_CHAIN_ID));
    }

    /// @dev constructor cannot be called with zero address GAC
    function test_constructor_zero_address_gac() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new WormholeReceiverAdapter(address(42), address(0), _wormholeChainId(ETHEREUM_CHAIN_ID));
    }

    /// @dev constructor cannot be called with zero sender chain id
    function test_constructor_zero_chain_id() public {
        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        new WormholeReceiverAdapter(address(42), address(42), uint16(0));
    }

    /// @dev gets the name
    function test_name() public {
        assertEq(adapter.name(), "WORMHOLE");
    }

    /// @dev updates sender adapter
    function test_update_sender_adapter() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit SenderAdapterUpdated(contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"], address(42));

        adapter.updateSenderAdapter(address(42));

        assertEq(adapter.senderAdapter(), address(42));
        assertEq(adapter.senderChain(), uint16(2));
    }

    /// @dev only global owner can update sender adapter
    function test_update_sender_adapter_only_global_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        adapter.updateSenderAdapter(address(42));
    }
    /// @dev cannot update sender adapter with zero address

    function test_update_sender_adapter_zero_address_input() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        adapter.updateSenderAdapter(address(0));
    }

    /// @dev sets chain ID map
    function test_set_chain_id_map() public {
        vm.startPrank(owner);

        uint256[] memory origIds = new uint256[](1);
        origIds[0] = 1234;
        uint16[] memory whIds = new uint16[](1);
        whIds[0] = uint16(5678);
        adapter.setChainIdMap(origIds, whIds);

        assertEq(adapter.chainIdMap(1234), uint16(5678));
    }

    /// @dev only global owner can set chain ID map
    function test_set_chain_id_map_only_global_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        adapter.setChainIdMap(new uint256[](0), new uint16[](0));
    }

    /// @dev cannot set chain ID map with mismatched array lengths
    function test_set_chain_id_map_array_length_mismatched() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ARRAY_LENGTH_MISMATCHED.selector);
        adapter.setChainIdMap(new uint256[](0), new uint16[](1));
    }

    /// @dev receives Wormhole message
    function test_receive_wormhole_messages() public {
        vm.startPrank(POLYGON_RELAYER);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
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
            receiverAdapter: address(adapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectEmit(true, true, true, true, address(adapter));
        emit MessageIdExecuted(SRC_CHAIN_ID, msgId);

        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(2), bytes32("1234")
        );

        assertTrue(adapter.isMessageExecuted(msgId));
        assertTrue(adapter.deliveryHashStatus(bytes32("1234")));
    }

    /// @dev cannot receive message with invalid sender chain ID
    function test_receive_wormhole_messages_invalid_sender_chain_id() public {
        vm.startPrank(POLYGON_RELAYER);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
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
            receiverAdapter: address(adapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_SENDER_CHAIN_ID.selector);
        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(42), bytes32("1234")
        );
    }

    /// @dev cannot receive message with invalid sender adapter
    function test_receive_wormhole_messages_invalid_sender_adapter() public {
        vm.startPrank(POLYGON_RELAYER);

        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
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
            receiverAdapter: address(adapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_SENDER_ADAPTER.selector);
        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(address(43)), uint16(2), bytes32("1234")
        );
    }

    /// @dev cannot receive message that is already executed
    function test_receive_wormhole_messages_message_id_already_executed() public {
        vm.startPrank(POLYGON_RELAYER);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
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
            receiverAdapter: address(adapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(2), bytes32("1234")
        );
        vm.expectRevert(abi.encodeWithSelector(MessageExecutor.MessageIdAlreadyExecuted.selector, msgId));
        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(2), bytes32("1234")
        );
    }

    /// @dev cannot receive message with invalid receiver adapter
    function test_receive_wormhole_messages_invalid_receiver_adapter() public {
        vm.startPrank(POLYGON_RELAYER);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
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

        vm.expectRevert(Error.INVALID_RECEIVER_ADAPTER.selector);
        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(2), bytes32("1234")
        );
    }

    /// @dev cannot receive message with invalid final destination
    function test_receive_wormhole_messages_invalid_final_destination() public {
        vm.startPrank(POLYGON_RELAYER);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
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
            receiverAdapter: address(adapter),
            finalDestination: address(43),
            data: abi.encode(message)
        });

        vm.expectRevert(Error.INVALID_FINAL_DESTINATION.selector);
        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(2), bytes32("1234")
        );
    }

    /// @dev reverts if message fails to be received
    function test_receive_wormhole_messages_message_failure() public {
        vm.startPrank(POLYGON_RELAYER);

        address senderAdapter = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
        address receiverAddr = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
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
            receiverAdapter: address(adapter),
            finalDestination: receiverAddr,
            data: abi.encode(message)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                MessageExecutor.MessageFailure.selector, msgId, abi.encodePacked(Error.INVALID_TARGET.selector)
            )
        );
        adapter.receiveWormholeMessages(
            abi.encode(payload), new bytes[](0), TypeCasts.addressToBytes32(senderAdapter), uint16(2), bytes32("1234")
        );
    }
}
