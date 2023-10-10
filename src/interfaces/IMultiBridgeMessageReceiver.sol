// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../libraries/Message.sol";

/// @notice interface for the multi-bridge message receiver
interface IMultiBridgeMessageReceiver {
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
    event MessageExecutionScheduled(
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

    /// @notice emitted when the governance timelock address is updated.
    /// @param oldTimelock is the previous governance timelock contract address
    /// @param newTimelock is the new governance timelock contract address
    event GovernanceTimelockUpdated(address oldTimelock, address newTimelock);

    /// @notice Receive messages from allowed bridge receiver adapters.
    /// @dev Every receiver adapter should call this function with decoded MessageLibrary.Message
    /// @param _message is the message to be received
    function receiveMessage(MessageLibrary.Message calldata _message) external;

    /// @notice Sends a message, that has achieved quorum and has not yet expired, to the governance timelock for eventual execution.
    /// @param _msgId is the unique identifier of the message
    /// @param _execParams are the params for message execution
    function scheduleMessageExecution(bytes32 _msgId, MessageLibrary.MessageExecutionParams calldata _execParams)
        external;

    /// @notice adds or removes bridge receiver adapters.
    /// @param _receiverAdapters the list of receiver adapters to add or remove
    /// @param _operations the list of operations to perform for corresponding receiver adapters, true for add, false for remove
    function updateReceiverAdapters(address[] calldata _receiverAdapters, bool[] calldata _operations) external;

    /// @notice updates the quorum for message validity, which is the number of bridges that must deliver the message for it to be considered valid.
    /// @param _quorum is the new quorum value
    function updateQuorum(uint64 _quorum) external;

    /// @notice updates the the list of receiver adapters and the quorum for message validity.
    /// @param _receiverAdapters the list of receiver adapters to add or remove
    /// @param _operations the list of operations to perform for corresponding receiver adapters, true for add, false for remove
    /// @param _newQuorum is the new quorum value
    function updateReceiverAdaptersAndQuorum(
        address[] calldata _receiverAdapters,
        bool[] calldata _operations,
        uint64 _newQuorum
    ) external;

    /// @notice updates the governance timelock address, which is the contract that ultimately executes valid messages.
    /// @param  _newGovernanceTimelock is the new governance timelock contract address
    function updateGovernanceTimelock(address _newGovernanceTimelock) external;
}
