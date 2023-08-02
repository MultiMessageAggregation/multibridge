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
    error INVALID_PRIVILAGED_CALLER();

    /// @dev is thrown if no sender adapter is found on MMA Sender
    error NO_SENDER_ADAPTER_FOUND();

    /// @dev is thrown if bridge adapter already delivered the message to multi message receiver
    error DUPLICATE_MESSAGE_DELIVERY_BY_ADAPTER();

    /*/////////////////////////////////////////////////////////////////
                                ADAPTER ERRORS
    ////////////////////////////////////////////////////////////////*/

    /// @dev is thrown if caller is not multi message sender
    error CALLER_NOT_MULTI_MESSAGE_SENDER();

    /// @dev is thrown if sender chain is not allowed on reciever adapter
    error INVALID_SENDER_CHAIN_ID();

    /// @dev is thrown if sender adapter is not allowed on reciever adapter
    error INVALID_SENDER_ADAPTER();

    /// @dev is thrown if final destination is not mma receiver on reciever adapter
    error INVALID_FINAL_DESTINATION();

    /// @dev is thrown if chain id is zero
    error ZERO_CHAIN_ID();

    /// @dev is thrown if receiverAdapter in decoded message is not the same
    error RECEIVER_ADAPTER_MISMATCHED();

    /// @dev is thrown if receiver adapter is zero address
    error ZERO_RECEIVER_ADAPTER();

    /// @dev is thrown when caller is not wormhole relayer
    error CALLER_NOT_WORMHOLE_RELAYER();

    /// @dev is thrown when hyperlane mailbox address is zero
    error ZERO_MAILBOX_ADDRESS();

    /// @dev is thrown when the destination chain id is invalid
    error INVALID_DST_CHAIN();

    /// @dev is thrown if caller is not telepathy router
    error CALLER_NOT_TELEPATHY_ROUTER();

    /// @dev is thrown if source sender is invalid
    error INVALID_SOURCE_SENDER();

    /// @dev is thrown if caller is not router protocol's gateway
    error CALLER_NOT_ROUTER_GATEWAY();

    /// @dev is thrown if caller is not hyperlane's mailbox
    error CALLER_NOT_HYPERLANE_MAILBOX();

    /// @dev is thrown if caller is not celer's message bus
    error CALLER_NOT_CELER_BUS();

    /// @dev is thrown if caller is not de-bridge gate
    error CALLER_NOT_DEBRIDGE_GATE();

    /// @dev is thrown if msg.value is less than required fees
    error INSUFFICIENT_FEES();

    /// @dev is thrown if contract call is invalid (for axelar)
    error NOT_APPROVED_BY_GATEWAY();
}
