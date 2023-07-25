// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.9;

/// @dev imported from https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/interfaces/IMessageRecipient.sol
interface IMessageRecipient {
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external;
}
