// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../BaseSenderAdapter.sol";

import "./interfaces/IMessageBus.sol";

/// @notice sender adapter for celer bridge
contract CelerSenderAdapter is BaseSenderAdapter {
    string public constant name = "celer";

    IMessageBus public immutable msgBus;

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _msgBus, address _gac) BaseSenderAdapter(_gac) {
        msgBus = IMessageBus(_msgBus);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice sends a message via celer message bus
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        onlyMultiMessageSender
        returns (bytes32 msgId)
    {
        if (_toChainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        address receiverAdapter = receiverAdapters[_toChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        msgId = _getNewMessageId(_toChainId, _to);
        bytes memory payload = abi.encode(AdapterPayload(msgId, msg.sender, receiverAdapter, _to, _data));

        IMessageBus(msgBus).sendMessage{value: msg.value}(receiverAdapter, _toChainId, payload);

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
    }

    /*/////////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function getMessageFee(uint256, address _to, bytes calldata _data) external view override returns (uint256) {
        /// @dev fee is depended only on message length
        return IMessageBus(msgBus).calcFee(abi.encode(bytes32(""), msg.sender, _to, _data));
    }
}
