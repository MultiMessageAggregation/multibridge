// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../EIP5164/MessageExecutor.sol";

/**
 * @notice A common interface for AMB message receiver adapters, that builds on EIP-5164 MessageExecutor.
 * A message receiver adapter receives messages through the AMB that are sent by a specific sender adapter on the source chain.
 * It validates the message and forwards it to the IMultiBridgeMessageReceiver contract on the destination chain.
 */
interface IMessageReceiverAdapter is MessageExecutor {
    /// @notice emitted when the sender adapter address, which resides on the source chain, is updated.
    /// @param oldSenderAdapter is the old sender adapter address
    /// @param newSenderAdapter is the new sender adapter address
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter);

    /// @notice returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @dev Changes the address of the sender adapter on the source chain, that is authorised to send this receiver messages.
    /// @param _senderAdapter is the bridge's sender adapter deployed on the source chain (i.e. Ethereum)
    /// note: access controlled to be called by the global admin contract
    function updateSenderAdapter(address _senderAdapter) external;
}
