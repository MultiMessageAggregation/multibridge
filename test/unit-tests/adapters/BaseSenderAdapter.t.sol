// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../../Setup.t.sol";
import "src/libraries/Error.sol";
import {AxelarSenderAdapter} from "src/adapters/axelar/AxelarSenderAdapter.sol";
import {BaseSenderAdapter} from "src/adapters/BaseSenderAdapter.sol";

contract AxelarSenderAdapterTest is Setup {
    event ReceiverAdapterUpdated(uint256 indexed dstChainId, address indexed oldReceiver, address indexed newReceiver);

    // Test base contract with Axelar adapter
    BaseSenderAdapter adapter;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        adapter = AxelarSenderAdapter(contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"]);
    }

    /// @dev updates receiver adapter
    function test_update_receiver_adapter() public {
        vm.startPrank(owner);

        address[] memory receiverAdapters = new address[](2);
        receiverAdapters[0] = address(42);
        receiverAdapters[1] = address(43);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit ReceiverAdapterUpdated(BSC_CHAIN_ID, adapter.receiverAdapters(BSC_CHAIN_ID), address(42));
        vm.expectEmit(true, true, true, true, address(adapter));
        emit ReceiverAdapterUpdated(POLYGON_CHAIN_ID, adapter.receiverAdapters(POLYGON_CHAIN_ID), address(43));

        adapter.updateReceiverAdapter(DST_CHAINS, receiverAdapters);

        assertEq(adapter.receiverAdapters(BSC_CHAIN_ID), address(42));
        assertEq(adapter.receiverAdapters(POLYGON_CHAIN_ID), address(43));
    }

    /// @dev only global owner can update receiver adapter
    function test_update_receiver_adapter_only_global_owner() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_OWNER.selector);
        adapter.updateReceiverAdapter(new uint256[](0), new address[](0));
    }

    /// @dev cannot update receiver adapter with invalid arrays
    function test_update_receiver_adapter_array_length_mismatched() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ARRAY_LENGTH_MISMATCHED.selector);
        adapter.updateReceiverAdapter(new uint256[](0), new address[](1));
    }
}
