// SPDX-License-Identifier: MIT OR Apache-2.0
// Extracted from https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/interfaces/IMailbox.sol
pragma solidity 0.8.17;

interface IMailbox {
    function dispatch(uint32 _destinationDomain, bytes32 _recipientAddress, bytes calldata _messageBody)
        external
        returns (bytes32);
}
