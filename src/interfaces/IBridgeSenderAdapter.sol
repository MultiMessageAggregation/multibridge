// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./EIP5164/SingleMessageDispatcher.sol";

/**
 * @dev Adapter that connects MultiMessageSender and each message bridge.
 * Message bridge can implement their favourite encode&decode way for MessageStruct.Message.
 */
interface IBridgeSenderAdapter is SingleMessageDispatcher {
    /**
     * @dev Return name of this message bridge.
     */
    function name() external view returns (string memory);

    /**
     * @dev Return native token amount in wei required by this message bridge for sending a message.
     */
    function getMessageFee(uint256 toChainId, address to, bytes calldata data) external view returns (uint256);

    /**
     * @dev Owner update receiver adapter address on dst chain.
     */
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters) external;
}
