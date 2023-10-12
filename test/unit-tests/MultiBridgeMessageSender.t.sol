// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

/// local imports
import "test/Setup.t.sol";
import "test/contracts-mock/FailingSenderAdapter.sol";
import "test/contracts-mock/ZeroAddressReceiverGAC.sol";
import "src/controllers/MessageSenderGAC.sol";
import "src/interfaces/adapters/IMessageSenderAdapter.sol";
import "src/interfaces/IMultiBridgeMessageReceiver.sol";
import "src/libraries/Error.sol";
import "src/libraries/Message.sol";
import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";

contract EthReceiverRevert {
    receive() external payable {
        revert();
    }
}

contract MultiBridgeMessageSenderTest is Setup {
    using MessageLibrary for MessageLibrary.Message;

    event MultiBridgeMessageSent(
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
    event SenderAdaptersUpdated(address[] indexed senderAdapters, bool add);
    event MessageSendFailed(address indexed senderAdapter, MessageLibrary.Message message);

    MultiBridgeMessageSender sender;
    address receiver;
    MessageSenderGAC senderGAC;
    address wormholeAdapterAddr;
    address axelarAdapterAddr;

    address revertingReceiver;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        sender = MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]);
        receiver = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        senderGAC = MessageSenderGAC(contractAddress[SRC_CHAIN_ID]["GAC"]);
        wormholeAdapterAddr = contractAddress[SRC_CHAIN_ID]["WORMHOLE_SENDER_ADAPTER"];
        axelarAdapterAddr = contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"];

        revertingReceiver = address(new EthReceiverRevert());
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(sender.senderGAC()), contractAddress[SRC_CHAIN_ID]["GAC"]);
    }

    /// @dev cannot be called with zero address GAC
    function test_constructor_zero_address_input() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new MultiBridgeMessageSender(address(0));
    }

    /// @dev perform remote call
    function test_remote_call() public {
        vm.startPrank(caller);

        // Wormhole requires exact fees to be passed in
        (uint256 wormholeFee,) = IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(
            _wormholeChainId(DST_CHAIN_ID), 0, senderGAC.msgDeliveryGasLimit()
        );
        (address[] memory senderAdapters, uint256[] memory fees) =
            _sortTwoAdaptersWithFees(axelarAdapterAddr, wormholeAdapterAddr, 0.01 ether, wormholeFee);
        bool[] memory adapterSuccess = new bool[](2);
        adapterSuccess[0] = true;
        adapterSuccess[1] = true;

        uint256 expiration = EXPIRATION_CONSTANT;

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 1,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: block.timestamp + expiration
        });
        bytes32 msgId = message.computeMsgId();

        vm.expectEmit(true, true, true, true, address(sender));
        emit MultiBridgeMessageSent(
            msgId, 1, DST_CHAIN_ID, address(42), bytes("42"), 0, expiration, senderAdapters, adapterSuccess
        );

        sender.remoteCall{value: fees[0] + fees[1]}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            expiration,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );

        assertEq(sender.nonce(), 1);
    }

    /// @dev perform remote call with invalid refund receiver
    function test_remote_call_reverting_refund_receiver() public {
        vm.startPrank(caller);

        // Wormhole requires exact fees to be passed in
        (uint256 wormholeFee,) = IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(
            _wormholeChainId(DST_CHAIN_ID), 0, senderGAC.msgDeliveryGasLimit()
        );
        (, uint256[] memory fees) =
            _sortTwoAdaptersWithFees(axelarAdapterAddr, wormholeAdapterAddr, 0.01 ether, wormholeFee);
        bool[] memory adapterSuccess = new bool[](2);
        adapterSuccess[0] = true;
        adapterSuccess[1] = true;

        uint256 expiration = EXPIRATION_CONSTANT;

        vm.expectRevert("safeTransferETH: ETH transfer failed");
        sender.remoteCall{value: fees[0] + fees[1] + 1 ether}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            expiration,
            revertingReceiver,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev perform remote call, checking for refund
    function test_remote_call_refund() public {
        vm.startPrank(caller);

        // NOTE: caller is also configured as the refund address in this test setup
        uint256 expiration = EXPIRATION_CONSTANT;
        uint256 nativeValue = 2 ether;

        uint256 balanceBefore = refundAddress.balance;

        (uint256 wormholeFee,) = IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(
            _wormholeChainId(DST_CHAIN_ID), 0, senderGAC.msgDeliveryGasLimit()
        );
        (, uint256[] memory fees) =
            _sortTwoAdaptersWithFees(axelarAdapterAddr, wormholeAdapterAddr, 0.01 ether, wormholeFee);
        sender.remoteCall{value: nativeValue}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            expiration,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );

        uint256 balanceAfter = refundAddress.balance;
        assertEq(balanceAfter - balanceBefore, nativeValue - fees[0] - fees[1]);
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

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 1,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: block.timestamp + EXPIRATION_CONSTANT
        });
        bytes32 msgId = message.computeMsgId();

        uint256[] memory fees = new uint256[](1);
        (uint256 wormholeFee,) = IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(
            _wormholeChainId(DST_CHAIN_ID), 0, senderGAC.msgDeliveryGasLimit()
        );
        fees[0] = wormholeFee;

        vm.expectEmit(true, true, true, true, address(sender));
        emit MultiBridgeMessageSent(
            msgId, 1, DST_CHAIN_ID, address(42), bytes("42"), 0, EXPIRATION_CONSTANT, senderAdapters, adapterSuccess
        );

        sender.remoteCall{value: 0.01 ether}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD - excludedAdapters.length,
            excludedAdapters
        );
    }

    /// @dev perform remote call with an invalid excluded adapter list
    function test_remote_call_invalid_excluded_adapter_list() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;
        address[] memory duplicateExclusions = new address[](2);
        duplicateExclusions[0] = axelarAdapterAddr;
        duplicateExclusions[1] = axelarAdapterAddr;

        vm.expectRevert();
        sender.remoteCall{value: 1 ether}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            duplicateExclusions
        );

        address[] memory nonExistentAdapter = new address[](1);
        nonExistentAdapter[0] = address(42);
        vm.expectRevert();
        sender.remoteCall{value: 1 ether}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            duplicateExclusions
        );
    }

    /// @dev only caller can perform remote call
    function test_remote_call_only_caller() public {
        vm.startPrank(owner);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        vm.expectRevert(Error.INVALID_PRIVILEGED_CALLER.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev message expiration has to be within allowed range
    function test_remote_call_invalid_expiration() public {
        address[] memory excludedAdapters = new address[](0);
        uint256 invalidExpMin = sender.MIN_MESSAGE_EXPIRATION() - 1 days;
        uint256 invalidExpMax = sender.MAX_MESSAGE_EXPIRATION() + 1 days;

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        // test expiration validation in remoteCall() which does not accept excluded adapters
        vm.startPrank(caller);
        vm.expectRevert(Error.INVALID_EXPIRATION_DURATION.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            invalidExpMin,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );

        vm.expectRevert(Error.INVALID_EXPIRATION_DURATION.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            invalidExpMax,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );

        // test expiration validation in remoteCall() which accepts excluded adapters
        vm.startPrank(caller);
        vm.expectRevert(Error.INVALID_EXPIRATION_DURATION.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            invalidExpMin,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );

        vm.expectRevert(Error.INVALID_EXPIRATION_DURATION.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            invalidExpMax,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );
    }

    /// @dev refund address is the multi message sender (or) zero address
    function test_remote_call_invalid_refundAddress() public {
        // test refund address validation in remoteCall() which does not accept excluded adapters
        vm.startPrank(caller);
        address[] memory excludedAdapters = new address[](0);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;
        vm.expectRevert(Error.INVALID_REFUND_ADDRESS.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            address(0),
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );

        vm.expectRevert(Error.INVALID_REFUND_ADDRESS.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            contractAddress[SRC_CHAIN_ID]["MMA_SENDER"],
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );

        // test refund address validation in remoteCall() which accepts excluded adapters
        vm.startPrank(caller);
        vm.expectRevert(Error.INVALID_REFUND_ADDRESS.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            address(0),
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );

        vm.expectRevert(Error.INVALID_REFUND_ADDRESS.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            contractAddress[SRC_CHAIN_ID]["MMA_SENDER"],
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            excludedAdapters
        );
    }

    /// @dev dst chain cannot be the the sender chain
    function test_remote_call_chain_id_is_sender_chain() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        vm.expectRevert(Error.INVALID_DST_CHAIN.selector);
        sender.remoteCall(
            block.chainid,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev cannot call with dst chain ID of 0
    function test_remote_call_zero_chain_id() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        sender.remoteCall(
            0,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev cannot call with target address of 0
    function test_remote_call_zero_target_address() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        vm.expectRevert(Error.INVALID_TARGET.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(0),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev cannot call with receiver address of 0
    function test_remote_call_zero_receiver_address() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        MultiBridgeMessageSender dummySender = new MultiBridgeMessageSender(address(new ZeroAddressReceiverGAC(caller)));

        vm.expectRevert(Error.ZERO_RECEIVER_ADAPTER.selector);
        dummySender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev cannot call with no sender adapter
    function test_remote_call_no_sender_adapter_found() public {
        vm.startPrank(owner);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        // Remove both adapters
        address[] memory senderAdapters = _sortTwoAdapters(axelarAdapterAddr, wormholeAdapterAddr);

        sender.removeSenderAdapters(senderAdapters);

        vm.startPrank(caller);

        vm.expectRevert(Error.NO_SENDER_ADAPTER_FOUND.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev should proceed with the call despite one failing adapter, emitting an error message
    function test_remote_call_failing_adapter() public {
        vm.startPrank(owner);

        // Add failing adapter
        address[] memory addedSenderAdapters = new address[](1);
        address failingAdapterAddr = address(new FailingSenderAdapter{salt: _salt}());
        addedSenderAdapters[0] = failingAdapterAddr;
        sender.addSenderAdapters(addedSenderAdapters);

        vm.startPrank(caller);

        address[] memory senderAdapters = new address[](3);
        uint256[] memory fees = new uint256[](3);
        bool[] memory adapterSuccess = new bool[](3);
        (uint256 wormholeFee,) = IWormholeRelayer(POLYGON_RELAYER).quoteEVMDeliveryPrice(
            _wormholeChainId(DST_CHAIN_ID), 0, senderGAC.msgDeliveryGasLimit()
        );
        senderAdapters[0] = axelarAdapterAddr;
        senderAdapters[1] = wormholeAdapterAddr;
        senderAdapters[2] = failingAdapterAddr;
        fees[0] = 0.01 ether;
        fees[1] = wormholeFee;
        fees[2] = 0.01 ether;
        adapterSuccess[0] = true;
        adapterSuccess[1] = true;
        adapterSuccess[2] = false;
        (senderAdapters, fees, adapterSuccess) = _sortThreeAdaptersWithFeesAndOps(senderAdapters, fees, adapterSuccess);

        uint256 expiration = EXPIRATION_CONSTANT;

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: SRC_CHAIN_ID,
            dstChainId: DST_CHAIN_ID,
            target: address(42),
            nonce: 1,
            callData: bytes("42"),
            nativeValue: 0,
            expiration: block.timestamp + expiration
        });
        bytes32 msgId = message.computeMsgId();

        vm.expectEmit(true, true, true, true, address(sender));
        emit MessageSendFailed(failingAdapterAddr, message);

        vm.expectEmit(true, true, true, true, address(sender));
        emit MultiBridgeMessageSent(
            msgId, 1, DST_CHAIN_ID, address(42), bytes("42"), 0, expiration, senderAdapters, adapterSuccess
        );

        sender.remoteCall{value: 0.1 ether}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            expiration,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev cannot call with invalid fee array
    function test_remote_call_invalid_fees() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](1);
        fees[0] = 0.01 ether;

        vm.expectRevert(Error.INVALID_SENDER_ADAPTER_FEES.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev cannot call with msg.value less than total fees
    function test_remote_call_invalid_msg_value() public {
        vm.startPrank(caller);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0.01 ether;
        fees[1] = 0.01 ether;

        vm.expectRevert(Error.INVALID_MSG_VALUE.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            fees,
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    /// @dev adds two sender adapters
    function test_add_sender_adapters() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](2);
        adapters[0] = address(42);
        adapters[1] = address(43);

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdaptersUpdated(adapters, true);

        sender.addSenderAdapters(adapters);

        (address[] memory origAdapters) = _sortTwoAdapters(axelarAdapterAddr, wormholeAdapterAddr);
        assertEq(sender.senderAdapters(0), address(42));
        assertEq(sender.senderAdapters(1), address(43));
        assertEq(sender.senderAdapters(2), origAdapters[0]);
        assertEq(sender.senderAdapters(3), origAdapters[1]);
    }

    /// @dev add to empty sender adapters
    function test_add_sender_adapters_to_empty() public {
        vm.startPrank(owner);

        address[] memory removals = _sortTwoAdapters(axelarAdapterAddr, wormholeAdapterAddr);
        sender.removeSenderAdapters(removals);

        address[] memory additions = new address[](2);
        additions[0] = address(42);
        additions[1] = address(43);

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdaptersUpdated(additions, true);

        sender.addSenderAdapters(additions);

        assertEq(sender.senderAdapters(0), address(42));
        assertEq(sender.senderAdapters(1), address(43));
    }

    /// @dev adds sender adapters with higher addresses
    function test_add_sender_adapters_higher_addresses() public {
        vm.startPrank(owner);

        (address[] memory existingAdpSorted) = _sortTwoAdapters(wormholeAdapterAddr, axelarAdapterAddr);

        address[] memory adapters = new address[](2);
        address higherAddr0 = address(uint160(existingAdpSorted[1]) + 1);
        address higherAddr1 = address(uint160(existingAdpSorted[1]) + 2);
        adapters[0] = higherAddr0;
        adapters[1] = higherAddr1;

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdaptersUpdated(adapters, true);

        sender.addSenderAdapters(adapters);

        assertEq(sender.senderAdapters(0), existingAdpSorted[0]);
        assertEq(sender.senderAdapters(1), existingAdpSorted[1]);
        assertEq(sender.senderAdapters(2), higherAddr0);
        assertEq(sender.senderAdapters(3), higherAddr1);
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

    /// @dev additions must be in ascending order
    function test_add_sender_adapters_invalid_order() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.INVALID_SENDER_ADAPTER_ORDER.selector);
        address[] memory adapters = new address[](2);
        adapters[0] = address(43);
        adapters[1] = address(42);
        sender.addSenderAdapters(adapters);
    }

    /// @dev removes two sender adapters
    function test_remove_sender_adapters() public {
        vm.startPrank(owner);

        address[] memory adapters = _sortTwoAdapters(axelarAdapterAddr, wormholeAdapterAddr);

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdaptersUpdated(adapters, false);

        sender.removeSenderAdapters(adapters);

        vm.expectRevert();
        sender.senderAdapters(0);
    }

    /// @dev removes one sender adapter
    function test_remove_sender_adapters_one() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](1);
        adapters[0] = wormholeAdapterAddr;

        vm.expectEmit(true, true, true, true, address(sender));
        emit SenderAdaptersUpdated(adapters, false);

        sender.removeSenderAdapters(adapters);

        assertEq(sender.senderAdapters(0), axelarAdapterAddr);
    }

    /// @dev only owner can call
    function test_remove_sender_adapters_only_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        sender.removeSenderAdapters(new address[](0));
    }

    /// @dev cannot remove one nonexistent sender adapter
    function test_remove_sender_adapters_nonexistent_one() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](1);
        adapters[0] = address(42);

        vm.expectRevert(Error.SENDER_ADAPTER_NOT_EXIST.selector);
        sender.removeSenderAdapters(adapters);
    }

    /// @dev cannot remove two nonexistent sender adapters
    function test_remove_sender_adapters_nonexistent_two() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](2);
        adapters[0] = address(42);
        adapters[1] = address(43);

        vm.expectRevert(Error.SENDER_ADAPTER_NOT_EXIST.selector);
        sender.removeSenderAdapters(adapters);
    }

    /// @dev cannot remove three nonexistent sender adapters
    function test_remove_sender_adapters_nonexistent_three() public {
        vm.startPrank(owner);

        address[] memory adapters = new address[](3);
        adapters[0] = address(42);
        adapters[1] = address(43);
        adapters[2] = address(44);

        vm.expectRevert(Error.SENDER_ADAPTER_NOT_EXIST.selector);
        sender.removeSenderAdapters(adapters);
    }

    /// @dev if the message could not be sent through a sufficient number of bridge
    function test_revert_for_insufficient_number_of_bridges() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.MULTI_MESSAGE_SEND_FAILED.selector);
        sender.remoteCall(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            new uint256[](2),
            DEFAULT_SUCCESS_THRESHOLD,
            new address[](0)
        );
    }

    function test_revert_for_invalid_success_threshold() public {
        vm.startPrank(caller);

        uint256 nativeValue = 2 ether;
        uint256 invalidSuccessThrehsold = 10;

        vm.expectRevert(Error.MULTI_MESSAGE_SEND_FAILED.selector);
        sender.remoteCall{value: nativeValue}(
            DST_CHAIN_ID,
            address(42),
            bytes("42"),
            0,
            EXPIRATION_CONSTANT,
            refundAddress,
            new uint256[](2),
            invalidSuccessThrehsold,
            new address[](0)
        );
    }
}
