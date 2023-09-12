// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";
import "test/contracts-mock/MockUniswapReceiver.sol";

import {MultiMessageSender} from "src/MultiMessageSender.sol";
import {TimelockHandler} from "test/invariant-tests/handlers/TimelockHandler.sol";

contract ZeroBalanceInTimelockInvariant is Setup {
    TimelockHandler public handler;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        handler = new TimelockHandler(contractAddress[DST_CHAIN_ID]["TIMELOCK"]);
        targetContract(address(handler));
    }

    function invariant_testAlwaysBalanceInTimelockIsZero() public {
        assertEq(contractAddress[DST_CHAIN_ID]["TIMELOCK"].balance, 0);
    }
}
