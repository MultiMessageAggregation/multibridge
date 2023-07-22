// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./EIP5164/MessageExecutor.sol";

//// @dev interface for bridge receiver adapters
interface IBridgeReceiverAdapter is MessageExecutor {
    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter);

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev allows global admin to update the sender adapter
    /// @param _senderAdapter is the bridge's sender adapter deployed to Ethereum
    /// note: access controlled to be called by the global admin contract
    function updateSenderAdapter(address _senderAdapter) external;
}
