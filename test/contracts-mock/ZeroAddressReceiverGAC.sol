// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev A mock GAC with zero address receiver
contract ZeroAddressReceiverGAC {
    address immutable caller;

    constructor(address _caller) {
        caller = _caller;
    }

    function getRemoteMultiMessageReceiver(uint256) external pure returns (address _mmaReceiver) {
        return address(0);
    }

    function getAuthorisedCaller() external view returns (address) {
        return caller;
    }
}
