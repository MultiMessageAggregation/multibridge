// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "../EIP5164/SingleMessageDispatcher.sol";

/// @dev common interface for all message sender adapters of messaging bridges
interface IMessageSenderAdapter is SingleMessageDispatcher {
    /// @notice emitted when a the sender's corresponding receiver adapter on a remote chain is changed
    /// @param  dstChainId is the destination chain for which the receiver adapter is updated
    /// @param  oldReceiver is the old receiver adapter address
    /// @param  newReceiver is the new receiver adapter address
    event ReceiverAdapterUpdated(uint256 indexed dstChainId, address indexed oldReceiver, address indexed newReceiver);

    /// @notice allows owner to update the receiver adapters on different destination chains
    /// @param _dstChainIds are the destination chain IDs for which the receiver adapters are to be updated
    /// @param _receiverAdapters receiver adapter addresses for the corresponding destination chain ids in _dstChainIds
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters) external;

    /// @notice returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @notice return the fee (in native token wei) that would be charged by the bridge for the provided remote call
    /// @param _toChainId is the destination chain id
    /// @param _to is the destination address on the destination chain
    /// @param _data is the data to be sent to the destination chain
    function getMessageFee(uint256 _toChainId, address _to, bytes calldata _data) external view returns (uint256);

    /// @notice returns the bridge receiver adapter address for a given destination chain id
    /// @param _chainId is the destination chain whose receiver adapter address is to be returned
    function getReceiverAdapter(uint256 _chainId) external view returns (address);
}
