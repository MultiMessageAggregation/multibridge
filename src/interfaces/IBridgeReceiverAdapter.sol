// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "./EIP5164/MessageExecutor.sol";

//// @dev interface for bridge receiver adapters
interface IBridgeReceiverAdapter is MessageExecutor {
    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/
    event SenderAdapterUpdated(address indexed oldSenderAdapter, address indexed newSenderAdapter, bytes senderChain);

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @dev allows global admin to update the sender adapter
    /// @param _senderChain is the bridge native sender chain (ETH) as bytes
    /// @param _senderAdapter is the bridge's sender adapter deployed to Ethereum
    /// note: access controlled to be called by the global admin contract
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external;
}
