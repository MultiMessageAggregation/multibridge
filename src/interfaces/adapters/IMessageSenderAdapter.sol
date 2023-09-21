// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "../EIP5164/SingleMessageDispatcher.sol";

/// @dev common interface for all message sender adapters of messaging bridges
interface IMessageSenderAdapter is SingleMessageDispatcher {
    /// @notice emitted when a the sender's corresponding receiver adapter on a remote chain is changed
    /// @param  dstChainId is the destination chain for which the receiver adapter is updated
    /// @param  receiverAdapter is the new receiver adapter address
    event ReceiverAdapterUpdated(uint256 indexed dstChainId, address indexed receiverAdapter);

    /// @notice allows owner to update the receiver adapters on different destination chains
    /// @param _dstChainIds are the destination chain IDs for which the receiver adapters are to be updated
    /// @param _receiverAdapters receiver adapter addresses for the corresponding destination chain ids in _dstChainIds
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters) external;

    /// @notice returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @notice return native token amount in wei required by this message bridge for sending a message
    function getMessageFee(uint256 _toChainId, address _to, bytes calldata _data) external view returns (uint256);
}
