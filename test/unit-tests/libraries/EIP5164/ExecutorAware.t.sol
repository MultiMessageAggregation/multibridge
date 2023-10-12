// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/libraries/EIP5164/ExecutorAware.sol";

/// @dev helper to test abstract contract
contract ExecutorAwareTestClient is ExecutorAware {
    function addTrustedExecutor(address _executor) external returns (bool) {
        return _addTrustedExecutor(_executor);
    }

    function removeTrustedExecutor(address _executor) external returns (bool) {
        return _removeTrustedExecutor(_executor);
    }
}

contract ExecutorAwareTest is Test {
    ExecutorAwareTestClient public executorAware;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        executorAware = new ExecutorAwareTestClient();
    }

    /*///////////////////////////////////////////////////////////////
                            TEST CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev tests adding a trusted executor
    function test_add_trusted_executor() public {
        address executor = address(0x1234567890123456789012345678901234567890);
        bool added = executorAware.addTrustedExecutor(executor);

        assertEq(added, true);
        assertEq(executorAware.isTrustedExecutor(executor), true);
    }

    /// @dev tests removing a trusted executor
    function test_remove_trusted_executor() public {
        address executor = address(0x1234567890123456789012345678901234567890);
        executorAware.addTrustedExecutor(executor);

        bool removed = executorAware.removeTrustedExecutor(executor);

        assertEq(removed, true);
        assertEq(executorAware.isTrustedExecutor(executor), false);
    }

    /// @dev tests retrieval of trusted executors
    function test_get_trusted_executors() public {
        address executor1 = address(420);
        address executor2 = address(421);
        executorAware.addTrustedExecutor(executor1);
        executorAware.addTrustedExecutor(executor2);

        address[] memory executors = executorAware.getTrustedExecutors();

        assertEq(executors.length == 2, true);
        assertEq(executors[0], executor1);
        assertEq(executors[1], executor2);
    }

    /// @dev tests counting the number of trusted executors
    function test_trusted_executors_count() public {
        address executor1 = address(420);
        address executor2 = address(421);
        executorAware.addTrustedExecutor(executor1);
        executorAware.addTrustedExecutor(executor2);

        uint256 count = executorAware.trustedExecutorsCount();

        assertEq(count, 2);
    }
}
