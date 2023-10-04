// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/**
 * @notice interface for governance timelock on the destination chain.
 * @dev this contract is responsible for executing all cross-chain messages on the destination chain
 * after they have been queued for a configurable period of time.
 * This contract is also typically, the GAC (Global Access Controller) on the destination chain, ensuring that all
 * admin actions on the destination chain go through the same validation process and time delay as other governance actions.
 */
interface IGovernanceTimelock {
    /// @notice emitted when a transaction is scheduled for execution.
    /// @param txId is the generated unique identifier of the scheduled transaction
    /// @param target is the address to call by low-level call
    /// @param value is the value to pass to target by low-level call
    /// @param data is the abieencoded function selector and arguments data, to execute on target
    /// @param eta is the timestamp after which the transaction should be executed
    event TransactionScheduled(uint256 indexed txId, address indexed target, uint256 value, bytes data, uint256 eta);

    /// @notice emitted when a transaction is executed.
    /// @param txId is the unique identifier of the executed transaction, generated when the transaction was scheduled
    /// @param target is the address called as part of the execution
    /// @param value is the value passed to target by low-level call
    /// @param data is the abieencoded function selector and arguments data, executed on target
    /// @param eta is the timestamp after which the transaction should be executed
    event TransactionExecuted(uint256 indexed txId, address indexed target, uint256 value, bytes data, uint256 eta);

    /// @notice emitted when the time delay parameter is changed.
    /// @param oldDelay is the previous value of the time delay
    /// @param newDelay is the new value of the time delay
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// @notice emitted when the admin of the time lock contract is changed
    /// @param oldAdmin is the previous admin of the time lock contract
    /// @param newAdmin is the new admin of the time lock contract
    event AdminUpdated(address oldAdmin, address newAdmin);

    /// @notice Schedules the provided transaction for execution after a pre-configured delay period.
    /// @dev this function can only be called by the admin of the timelock contract.
    /// @param _target is the address to call by low-level call
    /// @param _value is the value to pass to target by low-level call
    /// @param _data is the abieencoded function selector and arguments data, to execute on target
    function scheduleTransaction(address _target, uint256 _value, bytes memory _data) external;

    /// @notice Executes a previously scheduled transaction if it has reached its ETA, but has not exceeded a grace period beyond that.
    /// @param _txId is the unique identifier of the executed transaction, generated when the transaction was scheduled
    /// @param _target is the address called as part of the execution
    /// @param _value is the value passed to target by low-level call
    /// @param _data is the abieencoded function selector and arguments data, executed on target
    /// @param _eta is the timestamp after which the transaction should be executed
    function executeTransaction(uint256 _txId, address _target, uint256 _value, bytes memory _data, uint256 _eta)
        external
        payable;

    /// @notice Changes the time period that transactions must be queued for before they can be executed.
    /// The new delay must still be within an allowed range.
    /// This function can only be invoked by the timelock contract itself, thus requiring that this change go
    /// through the process and time delays as other governance actions.
    function setDelay(uint256 _delay) external;

    /// @notice Changes the admin.
    /// This function can only be invoked by the timelock contract itself, thus requiring that this change go
    /// through the process and time delays as other governance actions.
    function setAdmin(address _newAdmin) external;
}
