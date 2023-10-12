// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/libraries/TypeCasts.sol";

/// @dev helper to test TypeCasts library
/// @dev library testing using foundry can only be done through helper contracts
/// @dev see https://github.com/foundry-rs/foundry/issues/2567
contract TypeCastsLibraryTestClient {
    function addressToBytes32(address _addr) external pure returns (bytes32) {
        return TypeCasts.addressToBytes32(_addr);
    }

    function bytes32ToAddress(bytes32 _buf) external pure returns (address) {
        return TypeCasts.bytes32ToAddress(_buf);
    }
}

contract TypeCastsTest is Test {
    TypeCastsLibraryTestClient public typeCastsLibraryTestClient;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        typeCastsLibraryTestClient = new TypeCastsLibraryTestClient();
    }

    /*///////////////////////////////////////////////////////////////
                            TEST CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev tests conversion of address to bytes32
    function test_address_to_bytes32() public {
        address testAddr = address(0x1234567890123456789012345678901234567890);
        bytes32 expected = bytes32(uint256(uint160(testAddr))); // Correct casting here
        bytes32 result = typeCastsLibraryTestClient.addressToBytes32(testAddr);

        assertEq(result, expected);
    }

    /// @dev tests conversion of bytes32 to address
    function test_bytes32_to_address() public {
        bytes32 testBytes = bytes32(uint256(uint160(0x1234567890123456789012345678901234567890)));

        address expected = address(uint160(uint256(testBytes))); // Correct casting here
        address result = typeCastsLibraryTestClient.bytes32ToAddress(testBytes);

        assertEq(result, expected);
    }
}
