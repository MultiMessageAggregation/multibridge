// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./EIP5164/MessageExecutor.sol";

/**
 * @dev Adapter that connects MultiMessageReceiver and each message bridge.
 */
interface IBridgeReceiverAdapter is MessageExecutor {
    /**
     * @dev Owner update sender adapter address on src chain.
     */
    function updateSenderAdapter(uint256[] calldata _srcChainIds, address[] calldata _senderAdapters) external;
}
