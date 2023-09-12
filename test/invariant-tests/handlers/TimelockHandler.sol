// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {GovernanceTimelock} from "src/controllers/GovernanceTimelock.sol";

contract TimelockHandler is CommonBase, StdCheats, StdUtils {
    GovernanceTimelock public timelock;

    modifier prank(address _prankster) {
        vm.startPrank(_prankster);
        _;
        vm.stopPrank();
    }

    constructor(address _timelock) {
        timelock = GovernanceTimelock(_timelock);
    }

    function setDelay(uint256 delay) external prank(address(timelock)) {
        delay = bound(delay, timelock.MINIMUM_DELAY(), timelock.MAXIMUM_DELAY());
        timelock.setDelay(delay);
    }

    function setAdmin(address newAdmin) external prank(address(timelock)) {
        vm.assume(newAdmin != address(0));
        timelock.setAdmin(newAdmin);
    }

    function scheduleTransaction(address _target, uint256 _value, bytes memory _data) public prank(timelock.admin()) {
        vm.assume(_target != address(0));
        vm.assume(_value != 0);
        timelock.scheduleTransaction(_target, _value, _data);
    }

    function executeTransaction(uint256 _txId, address _target, uint256 _value, bytes memory _data, uint256 _eta)
        external
        payable
    {
        vm.prank(timelock.admin());
        timelock.scheduleTransaction(_target, _value, _data);

        _eta = block.timestamp + timelock.delay();
        vm.warp(_eta + 1 seconds);
        vm.deal(address(this), _value);
        timelock.executeTransaction{value: _value}(timelock.txCounter(), _target, _value, _data, _eta);
    }
}
