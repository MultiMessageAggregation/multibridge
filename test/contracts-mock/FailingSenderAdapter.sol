// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev A mock sender adapter that always fails at dispatching messages
contract FailingSenderAdapter {
    function dispatchMessage(uint256, address, bytes calldata) external payable returns (bytes32) {
        revert();
    }
}
