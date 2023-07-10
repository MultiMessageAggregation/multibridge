// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

library MessageStruct {
    /**
     * @dev Message indicates a remote call to target contract on destination chain.
     *
     * @param dstChainId is the id of chain where this message is sent to.
     * @param nonce is an incrementing number held by MultiMessageSender to ensure msgId uniqueness
     * @param target is the contract to be called on dst chain.
     * @param callData is the data to be sent to target by low-level call(eg. address(target).call(callData)).
     * @param expiration is the unix time when the message expires, zero means never expire.
     * @param bridgeName is the message bridge name used for sending this message.
     */
    struct Message {
        uint64 dstChainId;
        uint32 nonce;
        address target;
        bytes callData;
        uint64 expiration;
        string bridgeName;
    }

    /**
     * @notice Compute message Id.
     * message.bridgeName is not included in the message id.
     */
    function computeMsgId(MessageStruct.Message memory _message, uint64 _srcChainId) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _srcChainId,
                    _message.dstChainId,
                    _message.nonce,
                    _message.target,
                    _message.callData,
                    _message.expiration
                )
            );
    }
}
