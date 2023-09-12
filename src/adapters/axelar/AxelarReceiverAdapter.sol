// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "forge-std/console.sol";

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IMultiMessageReceiver.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../../libraries/Message.sol";

import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarExecutable.sol";
import "./libraries/StringAddressConversion.sol";

/// @notice receiver adapter for axelar bridge
contract AxelarReceiverAdapter is IAxelarExecutable, IBridgeReceiverAdapter {
    using StringAddressConversion for string;

    string public constant name = "axelar";

    IAxelarGateway public immutable gateway;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                        STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    address public senderAdapter;
    string public senderChain;

    mapping(bytes32 => bool) public isMessageExecuted;
    mapping(bytes32 => bool) public commandIdStatus;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyGlobalOwner() {
        if (!gac.isGlobalOwner(msg.sender)) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                         CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _gateway, address _gac) {
        gateway = IAxelarGateway(_gateway);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external override onlyGlobalOwner {
        string memory _senderChainDecoded = abi.decode(_senderChain, (string));

        if (keccak256(abi.encode(_senderChainDecoded)) == keccak256(abi.encode(""))) {
            revert Error.ZERO_CHAIN_ID();
        }

        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;
        senderChain = _senderChainDecoded;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter, _senderChain);
    }

    /// @dev accepts new cross-chain messages from axelar gateway
    /// @inheritdoc IAxelarExecutable
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external override {
        /// @dev step-1: validate incoming chain id
        if (keccak256(bytes(sourceChain)) != keccak256(bytes(senderChain))) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the caller
        if (!gateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload))) {
            revert Error.NOT_APPROVED_BY_GATEWAY();
        }

        /// @dev step-3: validate the source address
        if (sourceAddress.toAddress() != senderAdapter) {
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(payload, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-4: check for duplicate message
        if (commandIdStatus[commandId] || isMessageExecuted[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        /// @dev step-5: validate the destination
        if (decodedPayload.finalDestination != gac.getMultiMessageReceiver(block.chainid)) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        isMessageExecuted[msgId] = true;
        commandIdStatus[commandId] = true;

        MessageLibrary.Message memory _data = abi.decode(decodedPayload.data, (MessageLibrary.Message));

        try IMultiMessageReceiver(decodedPayload.finalDestination).receiveMessage(_data, name) {
            emit MessageIdExecuted(_data.srcChainId, msgId);
        } catch (bytes memory lowLevelData) {
            revert MessageFailure(msgId, lowLevelData);
        }
    }
}
