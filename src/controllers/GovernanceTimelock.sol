// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// interfaces
import {IGovernanceTimelock} from "../interfaces/IGovernanceTimelock.sol";

/// libraries
import "../libraries/Error.sol";

contract GovernanceTimelock is IGovernanceTimelock {

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @notice A modifier used for restricting the caller of some functions to be this contract itself.
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Error.INVALID_SELF_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernanceTimelock
    function scheduleTransaction(address target, uint256 value, bytes memory data, uint256 eta) external override {}

    /// @inheritdoc IGovernanceTimelock
    function executeTransaction(address target, uint256 value, bytes memory data, uint256 eta) external override {}

    /// @inheritdoc IGovernanceTimelock
    function setDelay(uint256 delay) external override onlySelf {}

    /// @inheritdoc IGovernanceTimelock
    function setAdmin(address newAdmin) external override onlySelf {}
}