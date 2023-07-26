// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

interface IAxelarExecutable {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}
