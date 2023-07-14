// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "../MessageStruct.sol";
import "../MultiMessageSender.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";

contract MockCaller is AccessControl {
    bytes32 public constant CALLER_ROLE = keccak256("CALLER");
    MultiMessageSender public bridgeSender;

    error AdminBadRole();
    error CallerBadRole();

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert AdminBadRole();
        _;
    }

    modifier onlyCaller() {
        if (!hasRole(CALLER_ROLE, msg.sender)) revert CallerBadRole();
        _;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setMultiMessageSender(MultiMessageSender _bridgeSender) external onlyAdmin {
        bridgeSender = _bridgeSender;
    }

    function remoteCall(uint64 _dstChainId, address _multiMessageReceiver, address _target, bytes calldata _callData)
        external
        payable
        onlyCaller
    {
        uint256 totalFee = bridgeSender.estimateTotalMessageFee(_dstChainId, _multiMessageReceiver, _target, _callData);
        bridgeSender.remoteCall{value: totalFee}(_dstChainId, _multiMessageReceiver, _target, _callData, 0);
    }

    function addSenderAdapters(address[] calldata _senderAdapters) external onlyAdmin {
        bridgeSender.addSenderAdapters(0, _senderAdapters);
    }

    function removeSenderAdapters(address[] calldata _senderAdapters) external onlyAdmin {
        bridgeSender.removeSenderAdapters(0, _senderAdapters);
    }

    function drainNativeToken() external onlyAdmin {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    receive() external payable {}
}
