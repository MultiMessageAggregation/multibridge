// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm, Test} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";
import "test/contracts-mock/MockUniswapReceiver.sol";

/// handler import
import {SenderAdapterAddHandler} from "test/invariant-tests/handlers/SenderAdapterAdd.handler.sol";

/// @notice invariants for adding adapters to multi bridge sender
contract AdapterListInvariant is Setup {
    SenderAdapterAddHandler public handler;

    /// @notice initializes the setup
    function setUp() public override {
        /// @dev calls setup to spin up test contracts
        super.setUp();

        /// @dev selects fork and deploy the handlers
        vm.selectFork(fork[SRC_CHAIN_ID]);
        handler = new SenderAdapterAddHandler(
            contractAddress[SRC_CHAIN_ID]["GAC"],
            contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]
        );
        targetContract(address(handler));
    }

    /// @notice invariant-1: adding an adapter should always increase the length of the adapter list
    /// @notice invariant-2: once a trusted executor is added, its entry should exist in the adapter list
    /// @notice invariant-3:  the adapter list should never contain duplicates
    /// @notice invariant-4:  the adapter list should always be in orde
    function invariant_test_adapter_additions() public {
        MultiBridgeMessageSender targetContract = MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]);
        if (handler.success()) {
            uint256 currAdds = handler.currAdds();

            address newAddition = targetContract.senderAdapters(currAdds - 1);
            /// @dev if this asset passes then invariant-2 holds
            assertTrue(newAddition != address(0));

            /// @dev if this revert then the final index is currAdds - 1 and the invariant-1 holds
            try targetContract.senderAdapters(currAdds) {
                assertFalse(1 == 2);
            } catch {}

            /// @dev assertions for invariant-3 and invariant-4
            if (currAdds > 1) {
                for (uint256 i = currAdds; i > 0; i--) {
                    assertTrue(
                        targetContract.senderAdapters(i)
                            > targetContract.senderAdapters(i - 1)
                    );
                }
            }
        }
    }
}
