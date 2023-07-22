// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./EIP5164/SingleMessageDispatcher.sol";

/// @dev interface for bridge sender adapters
interface IBridgeSenderAdapter is SingleMessageDispatcher {
    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/
    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev allows owner to update the receiver adapters on different destination chains
    /// @param _dstChainIds are the destination chain identifier
    /// @param _receiverAdapters are different receiver adapters
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters) external;

    /*/////////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev returns name of the message bridge wrapped by the adapter
    function name() external view returns (string memory);

    /// @dev return native token amount in wei required by this message bridge for sending a message
    function getMessageFee(uint256 toChainId, address to, bytes calldata data) external view returns (uint256);
}
