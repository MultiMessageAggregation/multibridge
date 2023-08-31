// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev A mock GAC with zero address receiver
contract ZeroAddressReceiverGac {
    address immutable caller;

    constructor(address _caller) {
        caller = _caller;
    }

    function getMultiMessageReceiver(uint256) external pure returns (address _mmaReceiver) {
        return address(0);
    }

    function getMultiMessageCaller() external view returns (address) {
        return caller;
    }
}
