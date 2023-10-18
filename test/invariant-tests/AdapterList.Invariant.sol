// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm, Test} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";

/// handler import
import {AdapterListHandler} from "test/invariant-tests/handlers/AdapterList.handler.sol";

/// @notice invariants for maintaining adapter list on `MultiBridgeMessageSender`
contract AdapterListInvariant is Setup {
    AdapterListHandler public handler;

    /// @notice initializes the setup
    function setUp() public override {
        /// @dev calls setup to spin up test contracts
        super.setUp();

        /// @dev selects fork and deploy the handlers
        vm.selectFork(fork[SRC_CHAIN_ID]);
        handler = new AdapterListHandler(
            contractAddress[SRC_CHAIN_ID]["GAC"],
            contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]
        );

        /// @dev bind the handler as target for invariant
        targetContract(address(handler));
    }

    /// @notice invariant-1: adding an adapter should always increase the length of the adapter list
    /// @notice invariant-2: once a trusted executor is added, its entry should exist in the adapter list
    /// @notice invariant-3:  the adapter list should never contain duplicates
    /// @notice invariant-4:  the adapter list should always be in order

    /// @notice invariant-5: removing an adapter should always decrease the length of the adapter list
    /// @notice invariant-6: once a trusted executor is removed, it should not persist in the adapter list
    function invariant_test_adapter_additions() public {
        MultiBridgeMessageSender targetContract = MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]);

        if (handler.success()) {
            uint256 currAdds = handler.currAdds();

            address newAddition = targetContract.senderAdapters(currAdds - 1);
            /// @dev if this asset passes then invariant-2 holds
            assertTrue(newAddition != address(0));

            /// @dev if this revert invariant-1 and invariant-5 holds
            try targetContract.senderAdapters(currAdds) {
                assertFalse(1 == 2);
            } catch {}

            /// @dev assertions for invariant-3, invariant-4, invariant-5, invariant-6
            if (currAdds > 1) {
                for (uint256 i = currAdds; i > 0; i--) {
                    assertTrue(targetContract.senderAdapters(i) > targetContract.senderAdapters(i - 1));
                }
            }
        }
    }
}
