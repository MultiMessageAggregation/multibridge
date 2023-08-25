// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// interfaces
import "../interfaces/IGovernanceTimelock.sol";

/// libraries
import "../libraries/Error.sol";

contract GovernanceTimelock is IGovernanceTimelock {
    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    uint256 public constant MINIMUM_DELAY = 2 days;
    uint256 public constant MAXIMUM_DELAY = 14 days;

    uint256 public txCounter;
    uint256 public delay = MINIMUM_DELAY;

    /// @dev the admin should be multi-message receiver
    address public multiMessageReceiver;

    mapping(uint256 txId => ScheduledTransaction) public scheduledTransaction;
    mapping(uint256 txId => bool executed) public isExecuted;

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

    /// @notice A modifier used for restricting caller to mma receiver contract
    modifier onlyMultiMessageReceiver() {
        if (msg.sender != multiMessageReceiver) {
            revert Error.CALLER_NOT_MULTI_MESSAGE_RECEIVER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _multiMessageReceiver is the address of multiMessageReceiver
    constructor(address _multiMessageReceiver) {
        if (_multiMessageReceiver == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        multiMessageReceiver = _multiMessageReceiver;
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernanceTimelock
    function scheduleTransaction(address _target, uint256 _value, bytes memory _data)
        external
        override
        onlyMultiMessageReceiver
    {
        if (_target == address(0)) {
            revert Error.INVALID_TARGET();
        }

        /// increment tx counter
        ++txCounter;
        uint256 eta = block.timestamp + delay;

        scheduledTransaction[txCounter] = ScheduledTransaction(_target, _value, _data, eta);

        emit TransactionScheduled(txCounter, _target, _value, _data, eta);
    }

    /// @inheritdoc IGovernanceTimelock
    function executeTransaction(uint256 txId) external override {
        /// @dev validates the txId
        if (txId == 0 || txId > txCounter) {
            revert Error.INVALID_TX_ID();
        }

        /// @dev checks if tx is already executed;
        if (isExecuted[txId]) {
            revert Error.TX_ALREADY_EXECUTED();
        }

        ScheduledTransaction memory transaction = scheduledTransaction[txId];

        /// @dev checks timelock
        if (transaction.eta < block.timestamp) {
            revert Error.TX_TIMELOCKED();
        }

        isExecuted[txId] = true;

        (bool status,) = transaction.target.call(transaction.data);

        if (!status) {
            revert Error.EXECUTION_FAILS_ON_DST();
        }

        emit TransactionExecuted(txId, transaction.target, transaction.value, transaction.data, transaction.eta);
    }

    /// @inheritdoc IGovernanceTimelock
    function setDelay(uint256 _delay) external override onlySelf {
        if (delay < MINIMUM_DELAY) {
            revert Error.INVALID_DELAY_MIN();
        }

        if (delay > MAXIMUM_DELAY) {
            revert Error.INVALID_DELAY_MAX();
        }

        uint256 oldDelay = delay;
        delay = _delay;

        emit DelayUpdated(oldDelay, _delay);
    }

    /// @inheritdoc IGovernanceTimelock
    function setAdmin(address _newAdmin) external override onlySelf {
        if (_newAdmin == address(0)) {
            revert Error.ZERO_TIMELOCK_ADMIN();
        }

        address oldAdmin = multiMessageReceiver;
        multiMessageReceiver = _newAdmin;

        emit AdminUpdated(oldAdmin, _newAdmin);
    }
}
