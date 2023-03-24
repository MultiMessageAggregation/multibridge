// SPDX-License-Identifier: MIT OR Apache-2.0
// From https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/interfaces/IMessageRecipient.sol
pragma solidity 0.8.17;

interface IMessageRecipient {
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external;
}
