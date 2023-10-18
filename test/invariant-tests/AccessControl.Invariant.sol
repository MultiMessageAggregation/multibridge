// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm, Test} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";

/// handler import
import {AccessControlSenderHandler} from "test/invariant-tests/handlers/AccessControlSender.handler.sol";

contract AccessControlHandlerInvariant is Setup {
    AccessControlSenderHandler public handler;

    /// @notice nonce snapshot for assertions
    uint256 public localNonceState;

    function setUp() public override {
        /// @dev calls setup to spin up test contracts
        super.setUp();

        /// @dev selects fork and deploy the handlers
        vm.selectFork(fork[SRC_CHAIN_ID]);
        handler = new AccessControlSenderHandler(
            contractAddress[SRC_CHAIN_ID]["GAC"],
            contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]
        );

        /// @dev bind the handler as target for invariant
        targetContract(address(handler));
    }

    function invariant_test_acess_control_src() public {
        if (handler.lastCaller() == MessageSenderGAC(contractAddress[SRC_CHAIN_ID]["GAC"]).authorisedCaller()) {
            ++localNonceState;
        }
        assertEq(MultiBridgeMessageSender(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"]).nonce(), localNonceState);
    }
}
