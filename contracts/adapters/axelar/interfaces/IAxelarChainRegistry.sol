// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title IAxelarChainRegistry
 * @dev Interface for mapping chain IDs to chain names and fees that are valid for the Axelar Network.
 */
interface IAxelarChainRegistry {
    /**
     * @dev Returns the name of the chain associated with the given chain ID.
     * @param chainId The ID of the chain to retrieve the name for.
     * @return The name of the chain as a string.
     */
    function getChainName(uint256 chainId) external view returns (string memory);

    /**
     * @dev Returns the ID of the chain associated with the given chain name.
     * @param chainName The name of the chain to retrieve the ID for.
     * @return The ID of the chain as a uint256.
     */
    function getChainId(string calldata chainName)
        external
        view
        returns (uint256);

    /**
     * @dev Returns the fee associated with the given chain ID.
     * @param chainId The ID of the chain to retrieve the fee for.
     * @return The fee as a uint256 value.
     */
    function getFee(uint256 chainId, uint32 gasLimit)
        external
        view
        returns (uint256);
}
