// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

interface IAxelarExecutable {
    /// @param commandId is axelar specific message identifier
    /// @param sourceChain is the identifier for source chain
    /// @param sourceAddress is the message sender address on source chain
    /// @param payload is the cross-chain message sent
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}
