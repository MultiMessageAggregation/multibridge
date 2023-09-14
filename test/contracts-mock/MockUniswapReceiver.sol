// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev assumes mock interactor is the one that send / receives message using the MMA infra
contract MockUniswapReceiver {
    uint256 public i;

    function setValue() external {
        i = type(uint256).max;
    }
}
