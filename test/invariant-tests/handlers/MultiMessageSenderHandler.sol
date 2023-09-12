// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {GAC} from "src/controllers/GAC.sol";
import {MultiMessageSender} from "src/MultiMessageSender.sol";

contract MultiMessageSenderHandler is CommonBase, StdCheats, StdUtils {
    MultiMessageSender public multiMessageSender;
    GAC public gac;

    modifier prank(address _prankster) {
        vm.startPrank(_prankster);
        _;
        vm.stopPrank();
    }

    constructor(address _multiMessageSender, address _gac) {
        multiMessageSender = MultiMessageSender(_multiMessageSender);
        gac = GAC(_gac);
    }

    function remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address[] calldata _excludedAdapters
    ) external payable prank(gac.getMultiMessageCaller()) {
        uint256 fees =
            multiMessageSender.estimateTotalMessageFee(_dstChainId, address(0), _target, _callData, _nativeValue);

        vm.deal(address(this), fees);
        multiMessageSender.remoteCall{value: fees}(_dstChainId, _target, _callData, _nativeValue, _expiration);
    }
}
