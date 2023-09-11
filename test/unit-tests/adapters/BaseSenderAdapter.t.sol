// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../../Setup.t.sol";
import "src/libraries/Error.sol";
import {AxelarSenderAdapter} from "src/adapters/axelar/AxelarSenderAdapter.sol";

contract AxelarSenderAdapterTest is Setup {
    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    uint256 constant SRC_CHAIN_ID = 1;
    uint256 constant DST_CHAIN_ID = 137;

    // Test base contract with Axelar adapter
    AxelarSenderAdapter adapter;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[SRC_CHAIN_ID]);
        adapter = AxelarSenderAdapter(contractAddress[SRC_CHAIN_ID]["AXELAR_SENDER_ADAPTER"]);
    }

    /// @dev updates receiver adapter
    function test_update_receiver_adapter() public {
        vm.startPrank(owner);

        uint256[] memory dstChainIds = new uint256[](2);
        dstChainIds[0] = 56;
        dstChainIds[1] = DST_CHAIN_ID;
        address[] memory receiverAdapters = new address[](2);
        receiverAdapters[0] = address(42);
        receiverAdapters[1] = address(43);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit ReceiverAdapterUpdated(56, address(42));
        vm.expectEmit(true, true, true, true, address(adapter));
        emit ReceiverAdapterUpdated(DST_CHAIN_ID, address(43));

        adapter.updateReceiverAdapter(dstChainIds, receiverAdapters);

        assertEq(adapter.receiverAdapters(56), address(42));
        assertEq(adapter.receiverAdapters(DST_CHAIN_ID), address(43));
    }

    /// @dev only privileged caller can update receiver adapter
    function test_update_receiver_adapter_only_privileged_caller() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_PRIVILEGED_CALLER.selector);
        adapter.updateReceiverAdapter(new uint256[](0), new address[](0));
    }

    /// @dev cannot update receiver adapter with invalid arrays
    function test_update_receiver_adapter_array_length_mismatched() public {
        vm.startPrank(owner);

        vm.expectRevert(Error.ARRAY_LENGTH_MISMATCHED.selector);
        adapter.updateReceiverAdapter(new uint256[](0), new address[](1));
    }

    /// @dev gets chian ID
    function test_get_chain_id() public {
        assertEq(adapter.getChainId(), SRC_CHAIN_ID);
    }
}
