// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../libraries/Message.sol";

interface IMultiMessageReceiver {
    /**
     * @notice Receive messages from allowed bridge receiver adapters.
     * If the accumulated power of a message has reached the power threshold,
     * this message will be executed immediately, which will invoke an external function call
     * according to the message content.
     *
     * @dev Every receiver adapter should call this function with decoded MessageStruct.Message
     * when receiver adapter receives a message produced by a corresponding sender adapter on the source chain.
     */
    function receiveMessage(MessageLibrary.Message calldata _message, uint256 _srcChainId) external;
}
