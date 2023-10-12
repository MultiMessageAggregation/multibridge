// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/libraries/Message.sol";

/// @dev is a helper function to test library contracts
contract MessageHelper {
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
    MessageHelper messageHelper;

    function setUp() public {
        messageHelper = new MessageHelper();
    }

    /// @dev tests computation of message id
    function testComputeMsgId() public {
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

        bytes32 computedId = messageHelper.computeMsgId(message);

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

        assertTrue(computedId == expectedId, "Message ID does not match expected value");
    }

    /// @dev tests extraction of execution parameters from a message
    function testExtractExecutionParams() public {
        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: 1,
            dstChainId: 2,
            target: address(0x1234567890123456789012345678901234567890),
            nonce: 123,
            callData: hex"abcdef",
            nativeValue: 456,
            expiration: 10000
        });

        MessageLibrary.MessageExecutionParams memory params = messageHelper.extractExecutionParams(message);

        assertTrue(
            params.target == address(0x1234567890123456789012345678901234567890)
                && keccak256(params.callData) == keccak256(hex"abcdef") && params.value == 456 && params.nonce == 123
                && params.expiration == 10000,
            "Extracted execution parameters are incorrect"
        );
    }

    /// @dev tests computation of execution parameters hash directly from parameters
    function testComputeExecutionParamsHash() public {
        MessageLibrary.MessageExecutionParams memory params = MessageLibrary.MessageExecutionParams({
            target: address(0x1234567890123456789012345678901234567890),
            callData: hex"abcdef",
            value: 456,
            nonce: 123,
            expiration: 10000
        });

        bytes32 computedHash = messageHelper.computeExecutionParamsHash(params);
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                address(0x1234567890123456789012345678901234567890),
                hex"abcdef",
                uint256(456),
                uint256(123),
                uint256(10000)
            )
        );

        assertTrue(computedHash == expectedHash, "Execution parameters hash does not match expected value");
    }

    /// @dev tests computation of execution parameters hash from a message
    function testComputeExecutionParamsHashFromMessage() public {
        MessageLibrary.Message memory message = MessageLibrary.Message({
            srcChainId: 1,
            dstChainId: 2,
            target: address(0x1234567890123456789012345678901234567890),
            nonce: 123,
            callData: hex"abcdef",
            nativeValue: 456,
            expiration: 10000
        });

        bytes32 computedHash = messageHelper.computeExecutionParamsHashFromMessage(message);
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                address(0x1234567890123456789012345678901234567890),
                hex"abcdef",
                uint256(456),
                uint256(123),
                uint256(10000)
            )
        );

        assertTrue(computedHash == expectedHash, "Execution parameters hash from message does not match expected value");
    }
}
