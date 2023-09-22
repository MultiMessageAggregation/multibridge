// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../interfaces/adapters/IMessageReceiverAdapter.sol";
import "../controllers/MessageReceiverGAC.sol";

abstract contract BaseReceiverAdapter is IMessageReceiverAdapter {
    MessageReceiverGAC public immutable receiverGAC;
    address public senderAdapter;

    modifier onlyGlobalOwner() {
        if (!receiverGAC.isGlobalOwner(msg.sender)) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    constructor(address _receiverGAC) {
        if (_receiverGAC == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }
        receiverGAC = MessageReceiverGAC(_receiverGAC);
    }

    /// @inheritdoc IMessageReceiverAdapter
    function updateSenderAdapter(address _newSender) external override onlyGlobalOwner {
        if (_newSender == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldSender = senderAdapter;
        senderAdapter = _newSender;

        emit SenderAdapterUpdated(oldSender, _newSender);
    }
}
