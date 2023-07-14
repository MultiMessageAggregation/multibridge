// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.17;

import {ITelepathyRouter} from "./interfaces/ITelepathy.sol";
import {IBridgeSenderAdapter} from "../../interfaces/IBridgeSenderAdapter.sol";
import {BaseSenderAdapter} from "../base/BaseSenderAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TelepathySenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter, Ownable {
    /* ========== EVENTS ========== */

    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    /* ========== ERRORS ========== */

    error MismatchAdapterArrLength(uint256 chainIdsLength, uint256 adaptersLength);

    /* ========== STATE VARIABLES ========== */

    string public constant name = "telepathy";
    address public immutable telepathyRouter;

    /// @dev dstChainId => receiverAdapter
    mapping(uint256 => address) public receiverAdapters;

    /* ========== CONSTRUCTOR  ========== */

    constructor(address _telepathyRouter) {
        telepathyRouter = _telepathyRouter;
    }

    /* ========== EXTERNAL METHODS ========== */

    /// @dev Telepathy does not have a fee and will subsidize the cost of execution for these messages.
    function getMessageFee(uint256, address, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    /// @notice Send a message message to the Telepathy Router.
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        returns (bytes32)
    {
        bytes32 msgId = _getNewMessageId(_toChainId, _to);
        bytes memory message = abi.encode(msgId, msg.sender, _to, _data);

        ITelepathyRouter(telepathyRouter).send(uint32(_toChainId), receiverAdapters[_toChainId], message);
        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);

        return msgId;
    }

    /* ========== ADMIN METHODS ========== */

    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters)
        external
        override
        onlyOwner
    {
        if (_dstChainIds.length != _receiverAdapters.length) {
            revert MismatchAdapterArrLength(_dstChainIds.length, _receiverAdapters.length);
        }
        for (uint256 i; i < _dstChainIds.length; ++i) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);
        }
    }
}
