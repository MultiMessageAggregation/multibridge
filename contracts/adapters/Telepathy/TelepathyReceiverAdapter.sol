// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.17;

import {ITelepathyHandler} from "./interfaces/ITelepathy.sol";
import {IBridgeReceiverAdapter} from "../../interfaces/IBridgeReceiverAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TelepathyReceiverAdapter is IBridgeReceiverAdapter, ITelepathyHandler, Ownable {
    /* ========== EVENTS ========== */

    event SenderAdapterUpdated(uint256 srcChainId, address senderAdapter);

    /* ========== ERRORS ========== */

    error NotFromTelepathyRouter(address sender);
    error InvalidSenderAdapter(address senderAdapter);
    error MismatchAdapterArrLength(uint256 chainIdsLength, uint256 adaptersLength);

    /* ========== STATE VARIABLES ========== */

    address public immutable telepathyRouter;

    /// @dev srcChainId => senderAdapter
    mapping(uint256 => address) public senderAdapters;
    /// @dev msgId => isExecuted
    mapping(bytes32 => bool) public executedMessages;

    /* ========== CONSTRUCTOR  ========== */

    constructor(address _telepathyRouter) {
        telepathyRouter = _telepathyRouter;
    }

    /* ========== EXTERNAL METHODS ========== */
    
    /// @dev The checks for MessageIdAlreadyExecuted
    function handleTelepathy(uint32 _srcChainId, address _srcAddress, bytes memory _message) external returns (bytes4) {
        // Validation
        if (msg.sender != telepathyRouter) {
            revert NotFromTelepathyRouter(msg.sender);
        }
        (bytes32 msgId, address multiMessageSender, address multiMessageReceiver, bytes memory data) =
            abi.decode(_message, (bytes32, address, address, bytes));
        if (_srcAddress != senderAdapters[uint256(_srcChainId)]) {
            revert InvalidSenderAdapter(_srcAddress);
        }
        if (executedMessages[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }
        executedMessages[msgId] = true;

        // Pass message on to the MultiMessageReceiver
        (bool success, bytes memory lowLevelData) =
            multiMessageReceiver.call(abi.encodePacked(data, msgId, uint256(_srcChainId), multiMessageSender));
        if (!success) {
            revert MessageFailure(msgId, lowLevelData);
        }

        emit MessageIdExecuted(uint256(_srcChainId), msgId);
        return ITelepathyHandler.handleTelepathy.selector;
    }

    /* ========== ADMIN METHODS ========== */

    function updateSenderAdapter(uint256[] calldata _srcChainIds, address[] calldata _senderAdapters)
        external
        override
        onlyOwner
    {
        if (_srcChainIds.length != _senderAdapters.length) {
            revert MismatchAdapterArrLength(_srcChainIds.length, _senderAdapters.length);
        }
        for (uint256 i; i < _srcChainIds.length; ++i) {
            senderAdapters[_srcChainIds[i]] = _senderAdapters[i];
            emit SenderAdapterUpdated(_srcChainIds[i], _senderAdapters[i]);
        }
    }
}
