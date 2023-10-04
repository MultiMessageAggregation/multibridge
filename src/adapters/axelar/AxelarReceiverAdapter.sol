// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/adapters/IMessageReceiverAdapter.sol";
import "../../interfaces/IMultiBridgeMessageReceiver.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../../libraries/Message.sol";

import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarExecutable.sol";
import "./libraries/StringAddressConversion.sol";

import "../../controllers/MessageReceiverGAC.sol";
import "../BaseSenderAdapter.sol";
import "../BaseReceiverAdapter.sol";

/// @notice receiver adapter for axelar bridge
contract AxelarReceiverAdapter is BaseReceiverAdapter, IAxelarExecutable {
    using StringAddressConversion for string;

    string public constant name = "AXELAR";

    IAxelarGateway public immutable gateway;

    /*/////////////////////////////////////////////////////////////////
                        STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    string public senderChainId;

    mapping(bytes32 => bool) public isMessageExecuted;
    mapping(bytes32 => bool) public commandIdStatus;

    /*/////////////////////////////////////////////////////////////////
                         CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    /// @param _gateway is axelar gateway contract address.
    /// @param _senderChainId is the chain id of the sender chain.
    /// @param _receiverGAC is global access controller.
    constructor(address _gateway, string memory _senderChainId, address _receiverGAC)
        BaseReceiverAdapter(_receiverGAC)
    {
        if (_gateway == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        if (bytes(_senderChainId).length == 0) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        gateway = IAxelarGateway(_gateway);
        senderChainId = _senderChainId;
    }

    /*/////////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev accepts new cross-chain messages from axelar gateway
    /// @inheritdoc IAxelarExecutable
    function execute(
        bytes32 _commandId,
        string calldata _sourceChainId,
        string calldata _sourceAddress,
        bytes calldata _payload
    ) external override {
        /// @dev step-1: validate incoming chain id
        if (keccak256(bytes(_sourceChainId)) != keccak256(bytes(senderChainId))) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the source address
        if (_sourceAddress.toAddress() != senderAdapter) {
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// @dev step-3: validate the contract call
        if (!gateway.validateContractCall(_commandId, _sourceChainId, _sourceAddress, keccak256(_payload))) {
            revert Error.NOT_APPROVED_BY_GATEWAY();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(_payload, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-4: check for duplicate message
        if (commandIdStatus[_commandId] || isMessageExecuted[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        /// @dev step-5: validate the receive adapter
        if (decodedPayload.receiverAdapter != address(this)) {
            revert Error.INVALID_RECEIVER_ADAPTER();
        }

        /// @dev step-6: validate the destination
        if (decodedPayload.finalDestination != receiverGAC.multiBridgeMsgReceiver()) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        isMessageExecuted[msgId] = true;
        commandIdStatus[_commandId] = true;

        MessageLibrary.Message memory _data = abi.decode(decodedPayload.data, (MessageLibrary.Message));

        try IMultiBridgeMessageReceiver(decodedPayload.finalDestination).receiveMessage(_data) {
            emit MessageIdExecuted(_data.srcChainId, msgId);
        } catch (bytes memory lowLevelData) {
            revert MessageFailure(msgId, lowLevelData);
        }
    }
}
