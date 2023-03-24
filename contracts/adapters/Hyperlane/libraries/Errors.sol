// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

library Errors {
    /**
     * @notice Emitted when the zero address is passed as the mailbox.
     * @dev mailbox == address(0)
     */
    error InvalidMailboxZeroAddress();

    /**
     * @notice Emitted when the caller is not the trusted mailbox contract.
     * @dev msg.sender != mailbox
     */
    error UnauthorizedMailbox(address sender);

    /**
     * @notice Emitted when the adapter is set to the zero address.
     * @dev adapter == address(0)
     */
    error InvalidAdapterZeroAddress();

    /**
     * @notice Emitted when the address is not a trusted adapter for the chain.
     * @dev addr != adapters[chainId]
     */
    error UnauthorizedAdapter(uint256 chainId, address addr);

    /**
     * @notice Emitted when the length of the destination chain ids and adapter arrays doesn't match.
     * @dev chainIds.length != adapters.length.
     * @param chainIdsLength Length of chain ids array.
     * @param adaptersLength Length of adapters array.
     */
    error MismatchChainsAdaptersLength(uint256 chainIdsLength, uint256 adaptersLength);
}
