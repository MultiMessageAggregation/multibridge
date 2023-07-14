// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.17;

import "../interfaces/IBridgeSenderAdapter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../adapters/base/BaseSenderAdapter.sol";
import "../interfaces/IBridgeReceiverAdapter.sol";

contract MockAdapter is IBridgeSenderAdapter, Ownable, BaseSenderAdapter, IBridgeReceiverAdapter {
    string public constant name = "mock";
    // dstChainId => receiverAdapter address
    mapping(uint256 => address) public receiverAdapters;
    mapping(uint256 => address) public senderAdapters;
    mapping(bytes32 => bool) public executedMessages;

    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);
    event SenderAdapterUpdated(uint256 srcChainId, address senderAdapter);

    function getMessageFee(uint256, address, bytes calldata) external pure override returns (uint256) {
        return 0.001 ether;
    }

    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        returns (bytes32)
    {
        require(receiverAdapters[_toChainId] != address(0), "no receiver adapter");
        require(msg.value >= 0.001 ether, "insufficient fee");
        bytes32 msgId = _getNewMessageId(_toChainId, _to);
        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
        return msgId;
    }

    function executeMessage(
        address _srcContract,
        uint64 _srcChainId,
        bytes32 _msgId,
        address _multiMessageSender,
        address _multiMessageReceiver,
        bytes calldata _data
    ) external {
        require(_srcContract == senderAdapters[uint256(_srcChainId)], "not allowed message sender");
        if (executedMessages[_msgId]) {
            revert MessageIdAlreadyExecuted(_msgId);
        } else {
            executedMessages[_msgId] = true;
        }
        (bool ok, bytes memory lowLevelData) =
            _multiMessageReceiver.call(abi.encodePacked(_data, _msgId, uint256(_srcChainId), _multiMessageSender));
        if (!ok) {
            revert MessageFailure(_msgId, lowLevelData);
        } else {
            emit MessageIdExecuted(uint256(_srcChainId), _msgId);
        }
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

    function updateSenderAdapter(uint256[] calldata _srcChainIds, address[] calldata _senderAdapters)
        external
        override
        onlyOwner
    {
        require(_srcChainIds.length == _senderAdapters.length, "mismatch length");
        for (uint256 i; i < _srcChainIds.length; ++i) {
            senderAdapters[_srcChainIds[i]] = _senderAdapters[i];
            emit SenderAdapterUpdated(_srcChainIds[i], _senderAdapters[i]);
        }
    }
}
