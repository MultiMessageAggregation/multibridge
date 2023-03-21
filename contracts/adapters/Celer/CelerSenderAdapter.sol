// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.17;

import "./interfaces/IMessageBus.sol";
import "../../interfaces/IBridgeSenderAdapter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../base/BaseSenderAdapter.sol";

contract CelerSenderAdapter is IBridgeSenderAdapter, Ownable, BaseSenderAdapter {
    string public constant name = "celer";
    address public immutable msgBus;
    // dstChainId => receiverAdapter address
    mapping(uint256 => address) public receiverAdapters;

    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    constructor(address _msgBus) {
        msgBus = _msgBus;
    }

    function getMessageFee(
        uint256,
        address _to,
        bytes calldata _data
    ) external view override returns (uint256) {
        // fee is depended only on message length
        return IMessageBus(msgBus).calcFee(abi.encode(bytes32(""), msg.sender, _to, _data));
    }

    function dispatchMessage(
        uint256 _toChainId,
        address _to,
        bytes calldata _data
    ) external payable override returns (bytes32) {
        require(receiverAdapters[_toChainId] != address(0), "no receiver adapter");
        bytes32 msgId = _getNewMessageId(_toChainId, _to);
        IMessageBus(msgBus).sendMessage{value: msg.value}(
            receiverAdapters[_toChainId],
            _toChainId,
            abi.encode(msgId, msg.sender, _to, _data)
        );
        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
        return msgId;
    }

    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters)
        external
        override
        onlyOwner
    {
        require(_dstChainIds.length == _receiverAdapters.length, "mismatch length");
        for (uint256 i; i < _dstChainIds.length; ++i) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);
        }
    }
}
