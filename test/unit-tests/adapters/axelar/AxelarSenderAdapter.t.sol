// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../../../Setup.t.sol";
import "src/libraries/Error.sol";
import {AxelarSenderAdapter} from "src/adapters/axelar/AxelarSenderAdapter.sol";

contract AxelarSenderAdapterTest is Setup {
    event MessageDispatched(
        bytes32 indexed messageId, address indexed from, uint256 indexed receiverChainId, address to, bytes data
    );
    event ChainIDMappingUpdated(uint256 indexed origId, string oldAxlId, string newAxlId);

    address senderAddr;
    AxelarSenderAdapter adapter;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        senderAddr = contractAddress[SRC_CHAIN_ID]["MMA_SENDER"];
        adapter = AxelarSenderAdapter(contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(adapter.gasService()), ETH_GAS_SERVICE);
        assertEq(address(adapter.gateway()), ETH_GATEWAY);
        assertEq(address(adapter.senderGAC()), contractAddress[SRC_CHAIN_ID]["GAC"]);
    }

    /// @dev constructor cannot be called with zero address gas service
    function test_constructor_zero_address_relayer() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new AxelarSenderAdapter(address(0), address(42), address(42));
    }

    /// @dev constructor cannot be called with zero address gateway
    function test_constructor_zero_address_gateway() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new AxelarSenderAdapter(address(42), address(0), address(42));
    }

    /// @dev constructor cannot be called with zero address GAC
    function test_constructor_zero_address_gac() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new AxelarSenderAdapter(address(42), address(42), address(0));
    }

    /// @dev dispatches message
    function test_dispatch_message() public {
        vm.startPrank(senderAddr);
        vm.deal(senderAddr, 1 ether);

        bytes32 msgId =
            keccak256(abi.encodePacked(SRC_CHAIN_ID, DST_CHAIN_ID, uint256(0), address(adapter), address(42)));
        vm.expectEmit(true, true, true, true, address(adapter));
        emit MessageDispatched(msgId, senderAddr, DST_CHAIN_ID, address(42), bytes("42"));

        adapter.dispatchMessage{value: 0.01 ether}(DST_CHAIN_ID, address(42), bytes("42"));

        assertEq(adapter.nonce(), 1);
    }

    /// @dev only sender can dispatch message
    function test_dispatch_message_only_sender() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_MULTI_MESSAGE_SENDER.selector);
        adapter.dispatchMessage{value: 1 ether}(DST_CHAIN_ID, address(42), bytes("42"));
    }

    /// @dev cannot dispatch message with zero receiver adapter
    function test_dispatch_message_zero_receiver_adapter() public {
        vm.startPrank(senderAddr);
        vm.deal(senderAddr, 1 ether);

        vm.expectRevert(Error.ZERO_RECEIVER_ADAPTER.selector);
        adapter.dispatchMessage{value: 1 ether}(9999, address(42), bytes("42"));
    }

    /// @dev cannot dispatch message to invalid dst chain
    function test_dispatch_message_invalid_dst_chain() public {
        // clear chain ID map entry first
        vm.startPrank(owner);
        uint256[] memory origIds = new uint256[](1);
        origIds[0] = DST_CHAIN_ID;
        string[] memory axlIds = new string[](1);
        axlIds[0] = "";
        adapter.setChainIdMap(origIds, axlIds);

        vm.startPrank(senderAddr);
        vm.deal(senderAddr, 1 ether);

        vm.expectRevert(Error.INVALID_DST_CHAIN.selector);
        adapter.dispatchMessage{value: 1 ether}(DST_CHAIN_ID, address(42), bytes("42"));
    }

    /// @dev sets chain ID map
    function test_set_chain_id_map() public {
        vm.startPrank(owner);
        uint256[] memory origIds = new uint256[](1);
        origIds[0] = DST_CHAIN_ID;
        string[] memory axlIds = new string[](1);
        axlIds[0] = "42";

        vm.expectEmit(true, true, true, true, address(adapter));
        emit ChainIDMappingUpdated(origIds[0], adapter.chainIdMap(DST_CHAIN_ID), axlIds[0]);

        adapter.setChainIdMap(origIds, axlIds);

        assertEq(adapter.chainIdMap(DST_CHAIN_ID), "42");
    }

    /// @dev only global owner can set chain ID map
    function test_set_chain_id_map_only_global_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        adapter.setChainIdMap(new uint256[](0), new string[](0));
    }

    /// @dev cannot set chain ID map with invalid ID arrays
    function test_set_chain_id_map_array_length_mismatched() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ARRAY_LENGTH_MISMATCHED.selector);
        adapter.setChainIdMap(new uint256[](0), new string[](1));
    }

    /// @dev cannot set chain ID map with invalid chain ID
    function test_set_chain_id_map_zero_chain_id() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ZERO_CHAIN_ID.selector);
        adapter.setChainIdMap(new uint256[](1), new string[](1));
    }
}
