// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/IAxelarChainRegistry.sol";
import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarExecutable.sol";
import "./libraries/StringAddressConversion.sol";

/// @notice receiver adapter for axelar bridge
contract AxelarReceiverAdapter is IAxelarExecutable, IBridgeReceiverAdapter {
    IAxelarChainRegistry public immutable axelarChainRegistry;
    IAxelarGateway public immutable gateway;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                        STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    address public senderAdapter;
    mapping(bytes32 => bool) public executeMsgs;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                         CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _chainRegistry, address _gateway, address _gac) {
        gateway = IAxelarGateway(_gateway);
        axelarChainRegistry = IAxelarChainRegistry(_chainRegistry);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external override {
        bytes32 payloadHash = keccak256(payload);

        // Validate the Axelar contract call. This will revert if the call is not approved by the Axelar Gateway contract.
        if (!gateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash)) {
            revert Error.NOT_APPROVED_BY_GATEWAY();
        }

        // Get the source chain id by chain name
        uint256 srcChainId = axelarChainRegistry.getChainId(sourceChain);

        // Check if the sender is allowed.
        // The sender should be the address of the sender adapter contract on the source chain.
        if (StringAddressConversion.toAddress(sourceAddress) != senderAdapter) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        // Decode the payload
        (bytes32 msgId, address srcSender, address destReceiver, bytes memory data) =
            abi.decode(payload, (bytes32, address, address, bytes));

        // Check if the message has been executed
        if (executeMsgs[msgId]) revert MessageIdAlreadyExecuted(msgId);

        // Mark the message as executed
        executeMsgs[msgId] = true;

        // Call MultiBridgeReceiver contract to execute the message
        (bool ok, bytes memory lowLevelData) = destReceiver.call(abi.encodePacked(data, msgId, srcChainId, srcSender));

        if (!ok) {
            revert MessageFailure(msgId, lowLevelData);
        } else {
            // Emit the event if the message is executed successfully
            emit MessageIdExecuted(srcChainId, msgId);
        }
    }
}
