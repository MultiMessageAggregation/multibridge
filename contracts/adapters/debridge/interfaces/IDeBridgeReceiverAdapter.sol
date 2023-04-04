// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IDeBridgeReceiverAdapter {
    function executeMessage(
        address multiMessageSender,
        address multiMessageReceiver,
        bytes calldata data,
        bytes32 msgId
    ) external;
}
