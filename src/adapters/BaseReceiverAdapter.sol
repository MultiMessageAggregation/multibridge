// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../interfaces/IMessageReceiverAdapter.sol";
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
    function updateSenderAdapter(address _senderAdapter) external override onlyGlobalOwner {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }
}
