// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.17;

import "../../interfaces/IBridgeSenderAdapter.sol";
import "../../MessageStruct.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IMessageBus {
    /**
     * @notice Send a message to a contract on another chain.
     * Sender needs to make sure the uniqueness of the message Id, which is computed as
     * hash(type.MessageOnly, sender, receiver, srcChainId, srcTxHash, dstChainId, message).
     * If messages with the same Id are sent, only one of them will succeed at dst chain..
     * A fee is charged in the native gas token.
     * @param _receiver The address of the destination app contract.
     * @param _dstChainId The destination chain ID.
     * @param _message Arbitrary message bytes to be decoded by the destination app contract.
     */
    function sendMessage(address _receiver, uint256 _dstChainId, bytes calldata _message) external payable;

    function calcFee(bytes calldata _message) external view returns (uint256);
}

contract CelerSenderAdapter is IBridgeSenderAdapter, Ownable {
    string public constant name = "celer";
    address public multiBridgeSender;
    address public immutable msgBus;
    // dstChainId => receiverAdapter address
    mapping(uint64 => address) public receiverAdapters;

    modifier onlyMultiBridgeSender() {
        require(msg.sender == multiBridgeSender, "not multi-bridge msg sender");
        _;
    }

    constructor(address _msgBus) {
        msgBus = _msgBus;
    }

    function getMessageFee(MessageStruct.Message memory _message) external view override returns (uint256) {
        _message.bridgeName = name;
        return IMessageBus(msgBus).calcFee(abi.encode(_message));
    }

    function sendMessage(MessageStruct.Message memory _message) external payable override onlyMultiBridgeSender {
        _message.bridgeName = name;
        require(receiverAdapters[_message.dstChainId] != address(0), "no receiver adapter");
        IMessageBus(msgBus).sendMessage{value: msg.value}(
            receiverAdapters[_message.dstChainId],
            _message.dstChainId,
            abi.encode(_message)
        );
    }

    function updateReceiverAdapter(
        uint64[] calldata _dstChainIds,
        address[] calldata _receiverAdapters
    ) external onlyOwner {
        require(_dstChainIds.length == _receiverAdapters.length, "mismatch length");
        for (uint256 i = 0; i < _dstChainIds.length; i++) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
        }
    }

    function setMultiBridgeSender(address _multiBridgeSender) external onlyOwner {
        multiBridgeSender = _multiBridgeSender;
    }
}
