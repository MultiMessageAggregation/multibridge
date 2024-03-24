pragma solidity >=0.8.9;

/// library imports
import {Vm, Test} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";

/// handler import
import {BridgeAdapterHandler} from "test/invariant-tests/handlers/BridgeAdapter.Handler.sol";

/// @notice invariants for bridge adapters receiving messages
contract BridgeAdapterInvariant is Setup {
    BridgeAdapterHandler public handler;

    /// @notice initializes the setup
    function setUp() public override {
        /// @dev calls setup to spin up test contracts
        super.setUp();

        /// @dev selects fork and deploy the handlers
        vm.selectFork(fork[BSC_CHAIN_ID]);
        handler = new BridgeAdapterHandler(
            contractAddress[BSC_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"],
            contractAddress[BSC_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"],
            contractAddress[BSC_CHAIN_ID]["MMA_RECEIVER"]
        );

        /// @dev bind the handler as target for invariant
        targetContract(address(handler));
    }

    function invariant_test_bridge_adapter_receivers() public {
        if (handler.success() && handler.lastBridge() == 1) {
            assertTrue(
                WormholeReceiverAdapter(contractAddress[BSC_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"]).isMessageExecuted(
                    handler.lastMessageId()
                )
            );
            assertTrue(
                WormholeReceiverAdapter(contractAddress[BSC_CHAIN_ID]["WORMHOLE_RECEIVER_ADAPTER"]).deliveryHashStatus(
                    handler.lastMessageHash()
                )
            );
        }

        if (handler.success() && handler.lastBridge() == 2) {
            assertTrue(
                AxelarReceiverAdapter(contractAddress[BSC_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"]).isMessageExecuted(
                    handler.lastMessageId()
                )
            );
            assertTrue(
                AxelarReceiverAdapter(contractAddress[BSC_CHAIN_ID]["AXELAR_RECEIVER_ADAPTER"]).commandIdStatus(
                    handler.lastMessageHash()
                )
            );
        }
    }
}
