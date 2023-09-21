/// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

/// local imports
import "../../interfaces/IMessageReceiverAdapter.sol";
import "../../interfaces/IMultiMessageReceiver.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../../libraries/TypeCasts.sol";
import "../../libraries/Message.sol";

import "../../controllers/MessageReceiverGAC.sol";
import "../BaseReceiverAdapter.sol";

/// @notice receiver adapter for wormhole bridge
/// @dev allows wormhole relayers to write to receiver adapter which then forwards the message to
/// the MMA receiver.
contract WormholeReceiverAdapter is BaseReceiverAdapter, IWormholeReceiver {
    string public constant name = "WORMHOLE";
    address public immutable relayer;
    uint16 public immutable senderChain;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    mapping(bytes32 => bool) public isMessageExecuted;
    mapping(bytes32 => bool) public deliveryHashStatus;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/

    modifier onlyRelayerContract() {
        if (msg.sender != relayer) {
            revert Error.CALLER_NOT_WORMHOLE_RELAYER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _relayer is wormhole relayer.
    /// @param _senderChain is the chain id of the sender chain.
    /// @param _receiverGAC is global access controller.
    /// note: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/automatic-relayer
    constructor(address _relayer, uint16 _senderChain, address _receiverGAC) BaseReceiverAdapter(_receiverGAC) {
        if (_relayer == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        if (_senderChain == uint16(0)) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        relayer = _relayer;
        senderChain = _senderChain;
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override onlyRelayerContract {
        /// @dev validate the caller (done in modifier)
        /// @dev step-1: validate incoming chain id
        if (sourceChain != senderChain) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the source address
        if (TypeCasts.bytes32ToAddress(sourceAddress) != senderAdapter) {
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(payload, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-3: check for duplicate message
        if (isMessageExecuted[msgId] || deliveryHashStatus[deliveryHash]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        isMessageExecuted[decodedPayload.msgId] = true;
        deliveryHashStatus[deliveryHash] = true;

        /// @dev step-4: validate the receive adapter
        if (decodedPayload.receiverAdapter != address(this)) {
            revert Error.INVALID_RECEIVER_ADAPTER();
        }

        /// @dev step-5: validate the destination
        if (decodedPayload.finalDestination != receiverGAC.getMultiMessageReceiver()) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        MessageLibrary.Message memory _data = abi.decode(decodedPayload.data, (MessageLibrary.Message));

        try IMultiMessageReceiver(decodedPayload.finalDestination).receiveMessage(_data) {
            emit MessageIdExecuted(_data.srcChainId, msgId);
        } catch (bytes memory lowLevelData) {
            revert MessageFailure(msgId, lowLevelData);
        }
    }
}
