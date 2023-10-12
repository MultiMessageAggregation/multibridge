// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/adapters/axelar/libraries/StringAddressConversion.sol";

/// @dev helper for testing StringAddressConversion library
contract StringAddressConversionHelper {
    function toString(address _addr) external pure returns (string memory) {
        return StringAddressConversion.toString(_addr);
    }

    function toAddress(string calldata _addressString) external pure returns (address) {
        return StringAddressConversion.toAddress(_addressString);
    }
}

contract StringAddressConversionTest is Test {
    StringAddressConversionHelper public conversionHelper;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        conversionHelper = new StringAddressConversionHelper();
    }

    /*///////////////////////////////////////////////////////////////
                            TEST CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev tests conversion of address to string
    function testToString() public {
        address testAddr = address(0x1234567890123456789012345678901234567890);
        string memory result = conversionHelper.toString(testAddr);
        string memory expected = "0x1234567890123456789012345678901234567890";

        assertTrue(
            keccak256(bytes(result)) == keccak256(bytes(expected)), "Converted string does not match expected value"
        );
    }

    /// @dev tests conversion of string to address
    function testToAddress() public {
        string memory testString = "0x1234567890123456789012345678901234567890";
        address result = conversionHelper.toAddress(testString);
        address expected = address(0x1234567890123456789012345678901234567890);

        assertTrue(result == expected, "Converted address does not match expected value");
    }

    /// @dev tests invalid address conversion
    function testInvalidAddressStringConversion() public {
        string memory invalidAddressString = "1234567890123456789012345678901234567892";

        bytes4 selector = bytes4(keccak256(bytes("InvalidAddressString()")));
        vm.expectRevert(selector);
        conversionHelper.toAddress(invalidAddressString);
    }

    /// @dev tests short address string
    function testShortAddressStringConversion() public {
        string memory shortAddressString = "0x12345678901234567890123456789012345678";

        bytes4 selector = bytes4(keccak256(bytes("InvalidAddressString()")));
        vm.expectRevert(selector);
        conversionHelper.toAddress(shortAddressString);
    }

    /// @dev tests long address string
    function testLongAddressStringConversion() public {
        string memory longAddressString = "0x123456789012345678901234567890123456789012";

        bytes4 selector = bytes4(keccak256(bytes("InvalidAddressString()")));
        vm.expectRevert(selector);
        conversionHelper.toAddress(longAddressString);
    }

    /// @dev tests invalid prefix in address string
    function testInvalidPrefixAddressStringConversion() public {
        string memory invalidPrefixAddressString = "1x1234567890123456789012345678901234567890";

        bytes4 selector = bytes4(keccak256(bytes("InvalidAddressString()")));
        vm.expectRevert(selector);
        conversionHelper.toAddress(invalidPrefixAddressString);
    }

    /// @dev tests address string with invalid characters
    function testInvalidCharacterAddressStringConversion() public {
        string memory invalidCharacterAddressString = "0x12345678901234567890123456789012345678g0"; // 'g' is an invalid character

        bytes4 selector = bytes4(keccak256(bytes("InvalidAddressString()")));
        vm.expectRevert(selector);
        conversionHelper.toAddress(invalidCharacterAddressString);
    }
}
