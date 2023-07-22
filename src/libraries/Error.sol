// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @dev is a library that contains all the error codes
library Error {
    /*/////////////////////////////////////////////////////////////////
                            COMMON VALIDATION ERRORS
    ////////////////////////////////////////////////////////////////*/

    /// @dev is thrown when input is zero address
    error ZERO_ADDRESS_INPUT();

    /// @dev is thrown if the length of two arrays are mismatched
    error ARRAY_LENGTH_MISMATCHED();

    /// @dev is thrown if caller is not owner of the contract
    error INVALID_PREVILAGED_CALLER();

    /*/////////////////////////////////////////////////////////////////
                                ADAPTER ERRORS
    ////////////////////////////////////////////////////////////////*/
    /// @dev is thrown if chain id is zero
    error ZERO_CHAIN_ID();

    /// @dev is thrown if receiverAdapter in decoded message is not the same
    error RECEIVER_ADAPTER_MISMATCHED();

    /// @dev is thrown if receiver adapter is zero address
    error ZERO_RECEIVER_ADPATER();

    /// @dev is thrown when caller is not wormhole relayer
    error CALLER_NOT_WORMHOLE_RELAYER();
}
