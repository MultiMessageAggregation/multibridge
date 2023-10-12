// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Test, Vm} from "forge-std/Test.sol";

/// local imports
import "src/libraries/EIP5164/ExecutorAware.sol";

/// @dev helper to test abstract contract
contract ExecutorAwareHelper is ExecutorAware {
    function addTrustedExecutor(address _executor) external returns (bool) {
        return _addTrustedExecutor(_executor);
    }

    function removeTrustedExecutor(address _executor) external returns (bool) {
        return _removeTrustedExecutor(_executor);
    }
}

contract ExecutorAwareTest is Test {
    ExecutorAwareHelper public executorAware;

    /*///////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        executorAware = new ExecutorAwareHelper();
    }

    /*///////////////////////////////////////////////////////////////
                            TEST CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev tests adding a trusted executor
    function testAddTrustedExecutor() public {
        address executor = address(0x1234567890123456789012345678901234567890);
        bool added = executorAware.addTrustedExecutor(executor);

        assertTrue(added, "Executor should be added successfully");
        assertTrue(executorAware.isTrustedExecutor(executor), "Executor should be trusted after addition");
    }

    /// @dev tests removing a trusted executor
    function testRemoveTrustedExecutor() public {
        address executor = address(0x1234567890123456789012345678901234567890);
        executorAware.addTrustedExecutor(executor);

        bool removed = executorAware.removeTrustedExecutor(executor);

        assertTrue(removed, "Executor should be removed successfully");
        assertFalse(executorAware.isTrustedExecutor(executor), "Executor should no longer be trusted after removal");
    }

    /// @dev tests retrieval of trusted executors
    function testGetTrustedExecutors() public {
        address executor1 = address(420);
        address executor2 = address(421);
        executorAware.addTrustedExecutor(executor1);
        executorAware.addTrustedExecutor(executor2);

        address[] memory executors = executorAware.getTrustedExecutors();
        
        assertTrue(executors.length == 2, "There should be two trusted executors");
        assertTrue(executors[0] == executor1 || executors[1] == executor1, "Executor1 should be in the returned list");
        assertTrue(executors[0] == executor2 || executors[1] == executor2, "Executor2 should be in the returned list");
    }

    /// @dev tests counting the number of trusted executors
    function testTrustedExecutorsCount() public {
        address executor1 = address(420);
        address executor2 = address(421);
        executorAware.addTrustedExecutor(executor1);
        executorAware.addTrustedExecutor(executor2);

        uint256 count = executorAware.trustedExecutorsCount();
        
        assertTrue(count == 2, "There should be two trusted executors");
    }
}
