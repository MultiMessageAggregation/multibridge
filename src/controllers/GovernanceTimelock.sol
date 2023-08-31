// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// interfaces
import "../interfaces/IGovernanceTimelock.sol";

/// libraries
import "../libraries/Error.sol";

contract GovernanceTimelock is IGovernanceTimelock {
    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MINIMUM_DELAY = 2 days;
    uint256 public constant MAXIMUM_DELAY = 30 days;

    /// @notice The time window within which a transaction can be executed, following its ETA. Beyond this point a transaction is considered stale and cannot be executed.
    uint256 public constant GRACE_PERIOD = 14 days;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    uint256 public txCounter;
    uint256 public delay = MINIMUM_DELAY;

    /// @notice the admin is the one allowed to schedule events
    address public admin;

    mapping(uint256 txId => bytes32) public scheduledTransaction;
    mapping(uint256 txId => bool) public isExecuted;

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

    /// @notice A modifier used for restricting caller to admin contract
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert Error.CALLER_NOT_ADMIN();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _admin is the address of admin contract that schedule txs
    constructor(address _admin) {
        if (_admin == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        admin = _admin;
        emit AdminUpdated(address(0), _admin);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernanceTimelock
    function scheduleTransaction(address _target, uint256 _value, bytes memory _data) external override onlyAdmin {
        if (_target == address(0)) {
            revert Error.INVALID_TARGET();
        }

        /// increment tx counter
        ++txCounter;
        uint256 eta = block.timestamp + delay;

        scheduledTransaction[txCounter] = keccak256(abi.encodePacked(_target, _value, _data, eta));
        emit TransactionScheduled(txCounter, _target, _value, _data, eta);
    }

    /// @inheritdoc IGovernanceTimelock
    function executeTransaction(uint256 _txId, address _target, uint256 _value, bytes memory _data, uint256 _eta)
        external
        payable
        override
    {
        /// @dev validates the txId
        if (_txId == 0 || _txId > txCounter) {
            revert Error.INVALID_TX_ID();
        }

        /// @dev checks if tx is already executed;
        if (isExecuted[_txId]) {
            revert Error.TX_ALREADY_EXECUTED();
        }

        /// @dev check the input params against hash
        if (scheduledTransaction[_txId] != keccak256(abi.encodePacked(_target, _value, _data, _eta))) {
            revert Error.INVALID_TX_INPUT();
        }

        /// @dev checks timelock
        if (_eta > block.timestamp) {
            revert Error.TX_TIMELOCKED();
        }

        /// @dev checks if tx within execution period
        if (block.timestamp > _eta + GRACE_PERIOD) {
            revert Error.TX_EXPIRED();
        }

        /// @dev checks native funding
        if (msg.value != _value) {
            revert Error.INVALID_MSG_VALUE();
        }

        isExecuted[_txId] = true;

        (bool status,) = _target.call{value: _value}(_data);

        if (!status) {
            revert Error.EXECUTION_FAILS_ON_DST();
        }

        emit TransactionExecuted(_txId, _target, _value, _data, _eta);
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

        address oldAdmin = admin;
        admin = _newAdmin;

        emit AdminUpdated(oldAdmin, _newAdmin);
    }
}
