// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/adapters/axelar/libraries/StringAddressConversion.sol";

/// @dev helper for testing StringAddressConversion library
/// @dev library testing using foundry can only be done through helper contracts
/// @dev see https://github.com/foundry-rs/foundry/issues/2567
contract StringAddressConversionTestClient {
    function toString(address _addr) external pure returns (string memory) {
        return StringAddressConversion.toString(_addr);
    }

    function toAddress(string calldata _addressString) external pure returns (address) {
        return StringAddressConversion.toAddress(_addressString);
    }
}

contract StringAddressConversionTest is Test {
    StringAddressConversionTestClient public conversionHelper;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        conversionHelper = new StringAddressConversionTestClient();
    }

    /*///////////////////////////////////////////////////////////////
                            TEST CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev tests conversion of address to string
    function test_to_string() public {
        address testAddr = address(0x1234567890123456789012345678901234567890);
        string memory result = conversionHelper.toString(testAddr);
        string memory expected = "0x1234567890123456789012345678901234567890";

        assertEq(keccak256(bytes(result)), keccak256(bytes(expected)));
    }

    /// @dev tests conversion of string to address
    function test_to_address() public {
        string memory testString = "0x1234567890123456789012345678901234567890";
        address result = conversionHelper.toAddress(testString);
        address expected = address(0x1234567890123456789012345678901234567890);

        assertEq(result, expected);
    }

    /// @dev tests invalid address conversion
    function test_invalid_address_string_conversion() public {
        string memory invalidAddressString = "1234567890123456789012345678901234567892";

        bytes4 selector = StringAddressConversion.InvalidAddressString.selector;
        vm.expectRevert(selector);
        conversionHelper.toAddress(invalidAddressString);
    }

    /// @dev tests short address string
    function test_short_address_string_conversion() public {
        string memory shortAddressString = "0x12345678901234567890123456789012345678";

        bytes4 selector = StringAddressConversion.InvalidAddressString.selector;
        vm.expectRevert(selector);
        conversionHelper.toAddress(shortAddressString);
    }

    /// @dev tests long address string
    function test_long_address_string_conversion() public {
        string memory longAddressString = "0x123456789012345678901234567890123456789012";

        bytes4 selector = StringAddressConversion.InvalidAddressString.selector;
        vm.expectRevert(selector);
        conversionHelper.toAddress(longAddressString);
    }

    /// @dev tests invalid prefix in address string
    function test_invalid_prefix_address_string_conversion() public {
        string memory invalidPrefixAddressString = "1x1234567890123456789012345678901234567890";

        bytes4 selector = StringAddressConversion.InvalidAddressString.selector;
        vm.expectRevert(selector);
        conversionHelper.toAddress(invalidPrefixAddressString);
    }

    /// @dev tests address string with invalid characters
    function test_invalid_character_address_string_conversion() public {
        string memory invalidCharacterAddressString = "0x12345678901234567890123456789012345678g0"; // 'g' is an invalid character

        bytes4 selector = StringAddressConversion.InvalidAddressString.selector;
        vm.expectRevert(selector);
        conversionHelper.toAddress(invalidCharacterAddressString);
    }

    /// @dev tests conversion of string with lowercase hex characters to address
    function test_lowercase_hex_character_to_address() public {
        string memory testString = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd";
        address result = conversionHelper.toAddress(testString);
        address expected = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);

        assertEq(result, expected);
    }

    /// @dev tests conversion of string with uppercase hex characters to address
    function test_ppercase_hex_character_to_address() public {
        string memory testString = "0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD";
        address result = conversionHelper.toAddress(testString);
        address expected = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);

        assertEq(result, expected);
    }
}
