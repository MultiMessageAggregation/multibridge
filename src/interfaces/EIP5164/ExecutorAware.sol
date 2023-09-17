// SPDX-License-Identifier: GPL-3.0
// Copied from https://github.com/pooltogether/ERC5164/blob/main/src/abstract/ExecutorAware.sol
// Modifications:
//   1. support higher version of solidity
//   2. support multiple trustedExecutors

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/**
 * @title ExecutorAware abstract contract
 * @notice The ExecutorAware contract allows contracts on a receiving chain to execute messages from an origin chain.
 *         These messages are sent by the `MessageDispatcher` contract which live on the origin chain.
 *         The `MessageExecutor` contract on the receiving chain executes these messages
 *         and then forward them to an ExecutorAware contract on the receiving chain.
 * @dev This contract implements EIP-2771 (https://eips.ethereum.org/EIPS/eip-2771)
 *      to ensure that messages are sent by a trusted `MessageExecutor` contract.
 */

abstract contract ExecutorAware {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ============ Variables ============ */
    /// @notice Addresses of the trusted executor contracts.
    EnumerableSet.AddressSet private trustedExecutors;

    /* ============ External Functions ============ */

    /**
     * @notice Check whether the provided executor is trusted
     * @param _executor Address to check
     * @return Returns true if the provided executor is trusted
     */
    function isTrustedExecutor(address _executor) public view returns (bool) {
        return EnumerableSet.contains(trustedExecutors, _executor);
    }

    /**
     * @notice Get the list of trusted executors
     * @return Returns an array of trusted executors
     */
    function getTrustedExecutors() public view returns (address[] memory) {
        return EnumerableSet.values(trustedExecutors);
    }

    /**
     * @notice Get the total number of trusted executors
     * @return Returns the total number of trusted executors
     */
    function trustedExecutorsCount() public view returns (uint256) {
        return EnumerableSet.length(trustedExecutors);
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Add a new trusted executor, if it is has not already been registered as trusted.
     * @param _executor Address of the `MessageExecutor` contract
     * @return _success Returns true if the executor was not already registered, and was added successfully
     */
    function _addTrustedExecutor(address _executor) internal returns (bool) {
        return EnumerableSet.add(trustedExecutors, _executor);
    }

    /**
     * @notice Remove a trusted executor, if it is registered as trusted.
     * @param _executor Address of the `MessageExecutor` contract
     * @return _success Returns true if the executor was previously registered, and was removed successfully
     */
    function _removeTrustedExecutor(address _executor) internal returns (bool) {
        return EnumerableSet.remove(trustedExecutors, _executor);
    }
}
