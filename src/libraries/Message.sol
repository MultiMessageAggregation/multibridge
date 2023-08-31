// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @title MessageStruct
/// @dev library for cross-chain message & related helper functions
library MessageLibrary {
    /// @dev Message indicates a remote call to target contract on destination chain.
    /// @param srcChainId is the id of chain where this message is sent from
    /// @param dstChainId is the id of chain where this message is sent to
    /// @param nonce is an incrementing number held by MultiMessageSender to ensure msgId uniqueness
    /// @param target is the contract to be called on dst chain
    /// @param callData is the data to be sent to target by low-level call(eg. address(target).call(callData))
    /// @param nativeValue is the native token value to be sent to target in the low-level call(eg. address(target).call{value: nativeValue}(callData))
    /// @param expiration is the unix time when the message expires, zero means never expire
    struct Message {
        uint256 srcChainId;
        uint256 dstChainId;
        address target;
        uint256 nonce;
        bytes callData;
        uint256 nativeValue;
        uint256 expiration;
    }

    /// @notice computes the message id (32 byte hash of the encoded message parameters)
    /// @param _message is the cross-chain message
    function computeMsgId(Message memory _message) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                _message.srcChainId,
                _message.dstChainId,
                _message.nonce,
                _message.target,
                _message.callData,
                _message.nativeValue,
                _message.expiration
            )
        );
    }
}
