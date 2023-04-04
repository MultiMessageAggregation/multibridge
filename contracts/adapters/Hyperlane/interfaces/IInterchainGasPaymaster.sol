// SPDX-License-Identifier: MIT OR Apache-2.0
// From https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/main/solidity/interfaces/IInterchainGasPaymaster.sol
pragma solidity 0.8.17;

/**
 * @title IInterchainGasPaymaster
 * @notice Manages payments on a source chain to cover gas costs of relaying
 * messages to destination chains.
 */
interface IInterchainGasPaymaster {
    /**
     * @notice Emitted when a payment is made for a message's gas costs.
     * @param messageId The ID of the message to pay for.
     * @param gasAmount The amount of destination gas paid for.
     * @param payment The amount of native tokens paid.
     */
    event GasPayment(bytes32 indexed messageId, uint256 gasAmount, uint256 payment);

    function payForGas(
        bytes32 _messageId,
        uint32 _destinationDomain,
        uint256 _gasAmount,
        address _refundAddress
    ) external payable;

    function quoteGasPayment(uint32 _destinationDomain, uint256 _gasAmount) external view returns (uint256);
}
