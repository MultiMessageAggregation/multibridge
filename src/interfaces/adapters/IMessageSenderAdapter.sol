// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "../EIP5164/SingleMessageDispatcher.sol";

/**
 * @notice A common interface for AMB message sender adapters, that builds on EIP-5164 SingleMessageDispatcher.
 * A message sender adapter for a specific AMB is responsible for receiving messages from an MultiBridgeMessageSender
 * on the source chain and sending the message to corresponding receiver adapters on the intended destination chain.
 * The sender adapter keeps a list of the remote receiver adapters on each destination chain that it forwards messages to.
 */
interface IMessageSenderAdapter is SingleMessageDispatcher {
    /// @notice emitted when a the sender's corresponding receiver adapter on a destination chain is changed
    /// @param  dstChainId is the destination chain for which the receiver adapter is updated
    /// @param  oldReceiver is the old receiver adapter address
    /// @param  newReceiver is the new receiver adapter address
    event ReceiverAdapterUpdated(uint256 indexed dstChainId, address indexed oldReceiver, address indexed newReceiver);

    /// @notice Updates the corresponding message receiver adapters for different destination chains
    /// @param _dstChainIds are the destination chain IDs for which the receiver adapters are to be updated
    /// @param _receiverAdapters new receiver adapter addresses for the corresponding destination chain ids in _dstChainIds
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters) external;

    /// @notice returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @notice returns the bridge receiver adapter address for a given destination chain id
    /// @param _chainId is the destination chain whose receiver adapter address is to be returned
    function receiverAdapters(uint256 _chainId) external view returns (address);
}
