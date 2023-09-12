// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import {Vm} from "forge-std/Test.sol";

/// local imports
import "test/Setup.t.sol";
import "test/contracts-mock/MockUniswapReceiver.sol";

import {MultiMessageSender} from "src/MultiMessageSender.sol";
import {MultiMessageSenderHandler} from "test/invariant-tests/handlers/MultiMessageSenderHandler.sol";

contract ZeroBalanceInSenderInvariant is Setup {
    MultiMessageSenderHandler public handler;

    /// @dev initializes the setup
    function setUp() public override {
        super.setUp();

        handler =
        new MultiMessageSenderHandler(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"], contractAddress[SRC_CHAIN_ID]["GAC"]);
        targetContract(address(handler));
    }

    function invariant_testAlwaysBalanceInMMASenderIsZero() public {
        assertEq(contractAddress[SRC_CHAIN_ID]["MMA_SENDER"].balance, 0);
    }
}
