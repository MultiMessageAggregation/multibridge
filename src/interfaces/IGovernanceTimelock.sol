// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev interface for governance timelock before execution events on dst chain
interface IGovernanceTimelock {
    /// @notice Schedules the provided transaction for execution after a specified ETA.
    /// @dev this function can only be called by the bridge adapter on the remote chain
    /// @param target the contract to call
    /// @param value the amount to pass when calling target
    /// @param data the abieencoded function selector and arguments data, to execute on target
    /// @param eta the time after which this message can be executed. This has to at least be greater than the current blocktime + the pre-configured delay parameter
    function scheduleTransaction(address target, uint256 value, bytes memory data, uint256 eta) external;

    /// @notice Executes a previously scheduled transaction if it has reached its ETA.
    /// @param target the contract to call
    /// @param value the amount to pass when calling target
    /// @param data the abiencoded function selector and arguments data, to execute on target
    /// @param eta the time after which this message can be executed.
    function executeTransaction(address target, uint256 value, bytes memory data, uint256 eta) external;

    /// @notice Updates the minimum delay for a transaction before it can be executed.
    /// @dev This can only be invoked by through this timelock contract, thus requiring that an update go through the required time delay first.
    function setDelay(uint256 delay) external;

    /// @notice Updates the admin.
    /// @dev This can only be invoked by through this timelock contract, thus requiring that an update go through the required time delay first.
    function setAdmin(address newAdmin) external;
}
