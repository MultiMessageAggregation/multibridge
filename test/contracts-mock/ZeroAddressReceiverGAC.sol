// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev A mock GAC with zero address receiver
contract ZeroAddressReceiverGAC {
    address public immutable authorisedCaller;

    constructor(address _caller) {
        authorisedCaller = _caller;
    }

    function remoteMultiBridgeMessageReceiver(uint256) external pure returns (address _mmaReceiver) {
        return address(0);
    }
}
