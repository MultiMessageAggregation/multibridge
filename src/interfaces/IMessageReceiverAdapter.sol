// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "./EIP5164/MessageExecutor.sol";

//// @dev interface for message receiver adapters
interface IMessageReceiverAdapter is MessageExecutor {
    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter);

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @dev allows the admin to update the sender adapter
    /// @param _senderAdapter is the bridge's sender adapter deployed on the source chain (i.e. Ethereum)
    /// note: access controlled to be called by the global admin contract
    function updateSenderAdapter(address _senderAdapter) external;
}
