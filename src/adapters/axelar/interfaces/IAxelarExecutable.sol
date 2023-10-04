// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

interface IAxelarExecutable {
    /// @param _commandId is axelar specific message identifier
    /// @param _sourceChainId is the identifier for source chain
    /// @param _sourceAddress is the message sender address on source chain
    /// @param _payload is the cross-chain message sent
    function execute(
        bytes32 _commandId,
        string calldata _sourceChainId,
        string calldata _sourceAddress,
        bytes calldata _payload
    ) external;
}
