// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/libraries/Message.sol";

/// @dev is a helper function to test library contracts
/// @dev library testing using foundry can only be done through helper contracts
/// @dev see https://github.com/foundry-rs/foundry/issues/2567
contract MessageLibraryTestClient {
    using MessageLibrary for MessageLibrary.Message;

    function computeMsgId(MessageLibrary.Message memory _message) external pure returns (bytes32) {
        return _message.computeMsgId();
    }

    function extractExecutionParams(MessageLibrary.Message memory _message)
        external
        pure
        returns (MessageLibrary.MessageExecutionParams memory)
    {
        return _message.extractExecutionParams();
    }

    function computeExecutionParamsHash(MessageLibrary.MessageExecutionParams memory _params)
        external
        pure
        returns (bytes32)
    {
        return MessageLibrary.computeExecutionParamsHash(_params);
    }

    function computeExecutionParamsHashFromMessage(MessageLibrary.Message memory _message)
        external
        pure
        returns (bytes32)
    {
        return _message.computeExecutionParamsHash();
    }
}

contract MessageLibraryTest is Test {
    MessageLibraryTestClient messageLibraryTestClient;

    function setUp() public {
        messageLibraryTestClient = new MessageLibraryTestClient();
    }

    /// @dev tests computation of message id
    function test_compute_msg_id() public {
        // convert the string literal to bytes constant
        bytes memory callDataBytes = hex"abcdef";

        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: 1,
            dstChainId: 2,
            target: address(0x1234567890123456789012345678901234567890),
            nonce: 123,
            callData: callDataBytes,
            nativeValue: 456,
            expiration: 10000
        });

        bytes32 computedId = messageLibraryTestClient.computeMsgId(message);

        // Update the expectedId calculation to use the bytes constant
        bytes32 expectedId = keccak256(
            abi.encodePacked(
                uint256(1),
                uint256(2),
                uint256(123),
                address(0x1234567890123456789012345678901234567890),
                uint256(456),
                uint256(10000),
                callDataBytes
            )
        );

        assertEq(computedId, expectedId);
    }

    /// @dev tests extraction of execution parameters from a message
    function test_extract_execution_params() public {
        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: 1,
            dstChainId: 2,
            target: address(0x1234567890123456789012345678901234567890),
            nonce: 123,
            callData: hex"abcdef",
            nativeValue: 456,
            expiration: 10000
        });

        MessageLibrary.MessageExecutionParams memory params = messageLibraryTestClient.extractExecutionParams(message);

        assertEq(params.target, address(0x1234567890123456789012345678901234567890));
        assertEq(keccak256(params.callData), keccak256(hex"abcdef"));
        assertEq(params.value, 456);
        assertEq(params.nonce, 123);
        assertEq(params.expiration, 10000);
    }

    /// @dev tests computation of execution parameters hash directly from parameters
    function test_compute_execution_params_hash() public {
        MessageLibrary.MessageExecutionParams memory params = MessageLibrary.MessageExecutionParams({
            target: address(0x1234567890123456789012345678901234567890),
            callData: hex"abcdef",
            value: 456,
            nonce: 123,
            expiration: 10000
        });

        bytes32 computedHash = messageLibraryTestClient.computeExecutionParamsHash(params);
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                address(0x1234567890123456789012345678901234567890),
                hex"abcdef",
                uint256(456),
                uint256(123),
                uint256(10000)
            )
        );

        assertEq(computedHash, expectedHash);
    }

    /// @dev tests computation of execution parameters hash from a message
    function test_compute_execution_params_hash_from_message() public {
        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: 1,
            dstChainId: 2,
            target: address(0x1234567890123456789012345678901234567890),
            nonce: 123,
            callData: hex"abcdef",
            nativeValue: 456,
            expiration: 10000
        });

        bytes32 computedHash = messageLibraryTestClient.computeExecutionParamsHashFromMessage(message);
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                address(0x1234567890123456789012345678901234567890),
                hex"abcdef",
                uint256(456),
                uint256(123),
                uint256(10000)
            )
        );

        assertEq(computedHash, expectedHash);
    }
}
