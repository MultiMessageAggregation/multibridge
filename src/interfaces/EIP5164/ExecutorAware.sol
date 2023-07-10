// SPDX-License-Identifier: GPL-3.0
// Copied from https://github.com/pooltogether/ERC5164/blob/main/src/abstract/ExecutorAware.sol
// Modifications:
//   1. support higher version of solidity
//   2. support multiple trustedExecutor

pragma solidity ^0.8.16;

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
    /* ============ Variables ============ */

    /// @notice Address of the trusted executor contract.
    address[] public trustedExecutor;

    /* ============ External Functions ============ */

    /**
     * @notice Check which executor this contract trust.
     * @param _executor Address to check
     */
    function isTrustedExecutor(address _executor) public view returns (bool) {
        for (uint256 i; i < trustedExecutor.length; ++i) {
            if (trustedExecutor[i] == _executor) {
                return true;
            }
        }
        return false;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Add a new trusted executor.
     * @param _executor Address of the `MessageExecutor` contract
     */
    function _addTrustedExecutor(address _executor) internal {
        if (!isTrustedExecutor(_executor)) {
            trustedExecutor.push(_executor);
        }
    }

    /**
     * @notice Remove a trusted executor.
     * @param _executor Address of the `MessageExecutor` contract
     */
    function _removeTrustedExecutor(address _executor) internal {
        uint256 lastIndex = trustedExecutor.length - 1;
        for (uint256 i; i < trustedExecutor.length; ++i) {
            if (trustedExecutor[i] == _executor) {
                if (i < lastIndex) {
                    trustedExecutor[i] = trustedExecutor[lastIndex];
                }
                trustedExecutor.pop();
                return;
            }
        }
    }

    /**
     * @notice Retrieve messageId from message data.
     * @return _msgDataMessageId ID uniquely identifying the message that was executed
     */
    function _messageId() internal pure returns (bytes32 _msgDataMessageId) {
        _msgDataMessageId;

        if (msg.data.length >= 84) {
            assembly {
                _msgDataMessageId := calldataload(sub(calldatasize(), 84))
            }
        }
    }

    /**
     * @notice Retrieve fromChainId from message data.
     * @return _msgDataFromChainId ID of the chain that dispatched the messages
     */
    function _fromChainId() internal pure returns (uint256 _msgDataFromChainId) {
        _msgDataFromChainId;

        if (msg.data.length >= 52) {
            assembly {
                _msgDataFromChainId := calldataload(sub(calldatasize(), 52))
            }
        }
    }

    /**
     * @notice Retrieve signer address from message data.
     * @return _signer Address of the signer
     */
    function _msgSender() internal view returns (address payable _signer) {
        _signer = payable(msg.sender);

        if (msg.data.length >= 20 && isTrustedExecutor(_signer)) {
            assembly {
                _signer := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        }
    }
}
