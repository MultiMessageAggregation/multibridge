// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./GAC.sol";

contract MessageReceiverGAC is GAC {
    event MultiMessageReceiverUpdated(address indexed oldMMR, address indexed newMMR);

    address private multiMessageReceiver;

    function setMultiMessageReceiver(address _mmaReceiver) external onlyOwner {
        if (_mmaReceiver == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }
        address oldMMR = multiMessageReceiver;
        multiMessageReceiver = _mmaReceiver;

        emit MultiMessageReceiverUpdated(oldMMR, _mmaReceiver);
    }

    function getMultiMessageReceiver() external view returns (address) {
        return multiMessageReceiver;
    }
}
