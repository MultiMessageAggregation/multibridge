// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../libraries/Message.sol";

/// @notice interface for the multi-bridge message receiver
interface IMultiBridgeMessageReceiver {
    /// @notice encapsulates data that is relevant to a message's intended transaction execution.
    struct ExecutionData {
        // target contract address on the destination chain
        address target;
        // data to pass to target by low-level call
        bytes callData;
        // value to pass to target by low-level call
        uint256 value;
        // nonce of the message
        uint256 nonce;
        // expiration timestamp for the message beyond which it cannot be executed
        uint256 expiration;
    }

    /// @notice emitted when a message has been received from a single bridge.
    /// @param msgId is the unique identifier of the message
    /// @param bridgeName is the name of the bridge from which the message was received
    /// @param nonce is the nonce of the message
    /// @param receiverAdapter is the address of the receiver adapter that received the message
    event BridgeMessageReceived(
        bytes32 indexed msgId, string indexed bridgeName, uint256 nonce, address receiverAdapter
    );

    /// @notice emitted when a message has been queued for execution in the destination timelock contract.
    /// @param msgId is the unique identifier of the message
    /// @param target is the address of the final target address that will be called once the timelock matures
    /// @param nativeValue is the value that will be passed to the target address through low-level call
    /// @param nonce is the nonce of the message
    /// @param callData is the data that will be passed to the target address through low-level call
    event MessageExecuted(
        bytes32 indexed msgId, address indexed target, uint256 nativeValue, uint256 nonce, bytes callData
    );

    /// @notice emitted when receiver adapter of a specific bridge is updated.
    /// @param receiverAdapter is the new receiver adapter address
    /// @param add is true if the receiver adapter was added, false if removed
    event BridgeReceiverAdapterUpdated(address indexed receiverAdapter, bool add);

    /// @notice emitted when the quorum for message validity is updated.
    /// @param oldQuorum is the old quorum value
    /// @param newQuorum is the new quorum value
    event QuorumUpdated(uint64 oldQuorum, uint64 newQuorum);

    /// @notice Receive messages from allowed bridge receiver adapters.
    /// @dev Every receiver adapter should call this function with decoded MessageLibrary.Message
    /// @param _message is the message to be received
    function receiveMessage(MessageLibrary.Message calldata _message) external;

    /// @notice Sends a message, that has achieved quorum and has not yet expired, to the governance timelock for eventual execution.
    /// @param _msgId is the unique identifier of the message
    function executeMessage(bytes32 _msgId) external;

    /// @notice adds or removes bridge receiver adapters.
    /// @param _receiverAdapters the list of receiver adapters to add or remove
    /// @param _operations the list of operations to perform for corresponding receiver adapters, true for add, false for remove
    function updateReceiverAdapters(address[] calldata _receiverAdapters, bool[] calldata _operations) external;

    /// @notice updates the quorum for message validity, which is the number of bridges that must deliver the message for it to be considered valid.
    /// @param _quorum is the new quorum value
    function updateQuorum(uint64 _quorum) external;

    /// @notice updates the the list of receiver adapters and the quorum for message validity.
    /// @param _newQuorum is the new quorum value
    /// @param _receiverAdapters the list of receiver adapters to add or remove
    /// @param _operations the list of operations to perform for corresponding receiver adapters, true for add, false for remove
    function updateQuorumAndReceiverAdapter(
        uint64 _newQuorum,
        address[] calldata _receiverAdapters,
        bool[] calldata _operations
    ) external;
}
