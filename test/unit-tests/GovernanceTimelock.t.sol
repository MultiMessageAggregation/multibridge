// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "../Setup.t.sol";
import "src/libraries/Error.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

contract GovernanceTimelockTest is Setup {
    event TransactionScheduled(uint256 indexed txId, address indexed target, uint256 value, bytes data, uint256 eta);
    event TransactionExecuted(uint256 indexed txId, address indexed target, uint256 value, bytes data, uint256 eta);

    event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event AdminUpdated(address oldAdmin, address newAdmin);

    GovernanceTimelock timelock;
    address admin;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        vm.selectFork(fork[DST_CHAIN_ID]);
        // admin is set to the receiver in setup
        admin = contractAddress[DST_CHAIN_ID]["MMA_RECEIVER"];
        timelock = GovernanceTimelock(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
    }

    /// @dev constructor
    function test_constructor() public {
        // checks existing setup
        assertEq(address(timelock.admin()), admin);
        assertEq(timelock.delay(), 3 days);
        assertEq(timelock.txCounter(), 0);
    }

    /// @dev constructor emits events for updating admin and delay period
    function test_constructor_emits_events() public {
        vm.expectEmit(true, true, true, true);
        emit AdminUpdated(address(0), address(42));
        vm.expectEmit(true, true, true, true);
        emit DelayUpdated(0, 3 days);

        new GovernanceTimelock(address(42), 3 days);
    }

    /// @dev cannot be called with zero address admin
    function test_constructor_zero_address_input() public {
        vm.expectRevert(Error.ZERO_ADDRESS_INPUT.selector);
        new GovernanceTimelock(address(0), 3 days);
    }

    /// @dev schedule transaction
    function test_schedule_transaction() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();

        vm.expectEmit(true, true, true, true, address(timelock));
        emit TransactionScheduled(1, address(42), 1, bytes("42"), eta);

        timelock.scheduleTransaction(address(42), 1, bytes("42"));

        assertEq(timelock.txCounter(), 1);
        assertEq(
            timelock.scheduledTransaction(1), keccak256(abi.encodePacked(address(42), uint256(1), eta, bytes("42")))
        );
    }

    /// @dev only admin can schedule transaction
    function test_schedule_transaction_only_admin() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.CALLER_NOT_ADMIN.selector);
        timelock.scheduleTransaction(address(42), 1, bytes("42"));
    }

    /// @dev cannot call with target address of 0
    function test_schedule_transaction_zero_target_address() public {
        vm.startPrank(admin);

        vm.expectRevert(Error.INVALID_TARGET.selector);
        timelock.scheduleTransaction(address(0), 1, bytes("42"));
    }

    /// @dev execute transaction
    function test_execute_transaction() public {
        vm.startPrank(admin);

        // schedule a transaction first
        uint256 eta = block.timestamp + timelock.delay();
        timelock.scheduleTransaction(address(42), 1, bytes("42"));

        // let timelock pass
        skip(timelock.delay());
        vm.startPrank(caller);

        vm.expectEmit(true, true, true, true, address(timelock));
        emit TransactionExecuted(1, address(42), uint256(1), bytes("42"), eta);

        timelock.executeTransaction{value: 1}(1, address(42), 1, bytes("42"), eta);

        assertTrue(timelock.isExecuted(1));
    }

    /// @dev cannot execute with zero tx ID
    function test_execute_transaction_zero_tx_id() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_TX_ID.selector);
        timelock.executeTransaction(0, address(42), 0, bytes("42"), block.timestamp);
    }

    /// @dev cannot execute with a tx ID too large
    function test_execute_transaction_tx_id_too_large() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_TX_ID.selector);
        timelock.executeTransaction(1, address(42), 0, bytes("42"), block.timestamp);
    }

    /// @dev cannot execute tx that is already executed
    function test_execute_transaction_already_executed() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();
        timelock.scheduleTransaction(address(42), 0, bytes("42"));
        skip(timelock.delay());

        vm.startPrank(caller);

        timelock.executeTransaction(1, address(42), 0, bytes("42"), eta);

        vm.expectRevert(Error.TX_ALREADY_EXECUTED.selector);
        timelock.executeTransaction(1, address(42), 0, bytes("42"), eta);
    }

    /// @dev cannot execute tx with wrong hash
    function test_execute_transaction_invalid_input() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();
        timelock.scheduleTransaction(address(42), 0, bytes("42"));
        skip(timelock.delay());

        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_TX_INPUT.selector);
        timelock.executeTransaction(1, address(42), 0, bytes("42"), eta + 1);
    }

    /// @dev cannot execute tx that is still timelocked
    function test_execute_transaction_timelocked() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();
        timelock.scheduleTransaction(address(42), 0, bytes("42"));

        vm.startPrank(caller);

        vm.expectRevert(Error.TX_TIMELOCKED.selector);
        timelock.executeTransaction(1, address(42), 0, bytes("42"), eta);
    }

    /// @dev cannot execute tx that has expired
    function test_execute_transaction_expired() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();
        timelock.scheduleTransaction(address(42), 0, bytes("42"));
        skip(timelock.delay() + timelock.GRACE_PERIOD() + 1);

        vm.startPrank(caller);

        vm.expectRevert(Error.TX_EXPIRED.selector);
        timelock.executeTransaction(1, address(42), 0, bytes("42"), eta);
    }

    /// @dev cannot execute tx with invalid value
    function test_execute_transaction_invalid_value() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();
        timelock.scheduleTransaction(address(42), 1, bytes("42"));
        skip(timelock.delay());

        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_MSG_VALUE.selector);
        timelock.executeTransaction(1, address(42), 1, bytes("42"), eta);
    }

    /// @dev failed to execute tx on dst chain
    function test_execute_transaction_fails_on_dst() public {
        vm.startPrank(admin);

        uint256 eta = block.timestamp + timelock.delay();
        // Use admin as dummy target address
        timelock.scheduleTransaction(admin, 0, bytes("42"));
        skip(timelock.delay());

        vm.startPrank(caller);

        vm.expectRevert(Error.EXECUTION_FAILS_ON_DST.selector);
        timelock.executeTransaction(1, admin, 0, bytes("42"), eta);
    }

    /// @dev sets delay
    function test_set_delay() public {
        vm.startPrank(address(timelock));

        uint256 oldDelay = timelock.delay();
        vm.expectEmit(true, true, true, true, address(timelock));
        emit DelayUpdated(oldDelay, 7 days);

        timelock.setDelay(7 days);
    }

    /// @dev only timelock can set delay
    function test_set_delay_only_self() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_SELF_CALLER.selector);
        timelock.setDelay(7 days);
    }

    /// @dev cannot set delay below minimum
    function test_set_delay_below_minimum() public {
        vm.startPrank(address(timelock));

        uint256 minDelay = timelock.MINIMUM_DELAY();
        vm.expectRevert(Error.INVALID_DELAY_MIN.selector);
        timelock.setDelay(minDelay - 1);
    }

    /// @dev cannot set delay above maximum
    function test_set_delay_above_maximum() public {
        vm.startPrank(address(timelock));

        uint256 maxDelay = timelock.MAXIMUM_DELAY();
        vm.expectRevert(Error.INVALID_DELAY_MAX.selector);
        timelock.setDelay(maxDelay + 1);
    }

    /// @dev sets admin
    function test_set_admin() public {
        vm.startPrank(address(timelock));

        address oldAdmin = timelock.admin();
        vm.expectEmit(true, true, true, true, address(timelock));
        emit AdminUpdated(oldAdmin, address(42));

        timelock.setAdmin(address(42));
    }

    /// @dev only timelock can set admin
    function test_set_admin_only_self() public {
        vm.startPrank(caller);

        vm.expectRevert(Error.INVALID_SELF_CALLER.selector);
        timelock.setAdmin(address(42));
    }

    /// @dev cannot set admin to zero address
    function test_set_admin_zero_address() public {
        vm.startPrank(address(timelock));

        vm.expectRevert(Error.ZERO_TIMELOCK_ADMIN.selector);
        timelock.setAdmin(address(0));
    }

    /// @dev sets delay via scheduled transaction
    function test_set_delay_scheduled() public {
        vm.startPrank(address(admin));

        bytes memory data = abi.encodeWithSelector(GovernanceTimelock.setDelay.selector, 10 days);
        timelock.scheduleTransaction(address(timelock), 0, data);
        uint256 eta = block.timestamp + timelock.delay();

        skip(3 days);

        timelock.executeTransaction(1, address(timelock), 0, data, eta);

        assertEq(timelock.delay(), 10 days);
    }

    /// @dev sets admin via scheduled transaction
    function test_set_admin_scheduled() public {
        vm.startPrank(address(admin));

        bytes memory data = abi.encodeWithSelector(GovernanceTimelock.setAdmin.selector, address(42));
        timelock.scheduleTransaction(address(timelock), 0, data);
        uint256 eta = block.timestamp + timelock.delay();

        skip(3 days);

        timelock.executeTransaction(1, address(timelock), 0, data, eta);

        assertEq(timelock.admin(), address(42));
    }
}
