// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev interface for governance timelock before execution events on dst chain
interface IGovernanceTimelock {
    /*/////////////////////////////////////////////////////////////////
                                STRUCTS
    ////////////////////////////////////////////////////////////////*/
    struct ScheduledTransaction {
        address target;
        uint256 value;
        bytes data;
        uint256 eta;
        uint256 expiry;
        bool isExecuted;
    }

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/
    event TransactionScheduled(
        uint256 indexed txId, address target, uint256 value, bytes data, uint256 eta, uint256 expiry
    );
    event TransactionExecuted(
        uint256 indexed txId, address target, uint256 value, bytes data, uint256 eta, uint256 expiry
    );

    event ExecutionPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event AdminUpdated(address oldAdmin, address newAdmin);

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Schedules the provided transaction for execution after a specified ETA.
    /// @dev this function can only be called by the bridge adapter on the remote chain
    /// @param _target the contract to call
    /// @param _value the amount to pass when calling target
    /// @param _data the abieencoded function selector and arguments data, to execute on target
    function scheduleTransaction(address _target, uint256 _value, bytes memory _data) external;

    /// @notice Executes a previously scheduled transaction if it has reached its ETA.
    /// @param _txId is the unqiue identifier of the scheduled transaction
    function executeTransaction(uint256 _txId) external payable;

    /// @notice Updates the minimum delay for a transaction before it can be executed.
    /// @dev This can only be invoked by through this timelock contract, thus requiring that an update go through the required time delay first.
    function setDelay(uint256 _delay) external;

    /// @notice Updates the period after timelock where the transaction can be executed
    /// @dev This can only be executed by through this timelock contract, thus requiring that an update go through the required time delay first.
    function setExecutionPeriod(uint256 _period) external;

    /// @notice Updates the admin.
    /// @dev This can only be invoked by through this timelock contract, thus requiring that an update go through the required time delay first.
    function setAdmin(address newAdmin) external;
}
