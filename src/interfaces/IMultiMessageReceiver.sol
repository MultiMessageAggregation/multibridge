// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../libraries/Message.sol";

interface IMultiMessageReceiver {
    /*/////////////////////////////////////////////////////////////////
                                    STRUCTS
    ////////////////////////////////////////////////////////////////*/
    struct ExecutionData {
        address target;
        bytes callData;
        uint256 value;
        uint256 nonce;
        uint256 expiration;
    }

    /*/////////////////////////////////////////////////////////////////
                                    EVENTS
    ////////////////////////////////////////////////////////////////*/
    event ReceiverAdapterUpdated(address receiverAdapter, bool add);
    event QuorumUpdated(uint64 oldValue, uint64 newValue);
    event SingleBridgeMsgReceived(
        bytes32 indexed msgId, string indexed bridgeName, uint256 nonce, address receiverAdapter
    );
    event MessageExecuted(bytes32 indexed msgId, address target, uint256 nativeValue, uint256 nonce, bytes callData);

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Receive messages from allowed bridge receiver adapters.
    /// If the accumulated power of a message has reached the power threshold,
    /// this message will be executed immediately, which will invoke an external function call
    /// according to the message content.

    /// @dev Every receiver adapter should call this function with decoded MessageStruct.Message
    /// when receiver adapter receives a message produced by a corresponding sender adapter on the source chain.
    function receiveMessage(MessageLibrary.Message calldata _message, string memory _bridgeName) external;
}
