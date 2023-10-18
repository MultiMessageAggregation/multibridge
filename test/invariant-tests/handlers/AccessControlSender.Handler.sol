// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "forge-std/Test.sol";

/// local imports
import {MessageSenderGAC} from "src/controllers/MessageSenderGAC.sol";
import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";

/// @notice handler for testing access control invariants
contract AccessControlSenderHandler is Test {
    /// @notice local state
    MultiBridgeMessageSender public multiBridgeMessageSender;
    MessageSenderGAC public gac;

    /// @notice logs last caller for validations
    address public lastCaller;

    /// @notice modifier to prank caller
    modifier prank(address _prankster) {
        vm.startPrank(_prankster);
        _;
        vm.stopPrank();
    }

    /// @notice initial setup contracts
    constructor(address _gac, address _multiBridge) {
        gac = MessageSenderGAC(_gac);
        multiBridgeMessageSender = MultiBridgeMessageSender(_multiBridge);
    }

    /// @notice helper for remote call
    function remoteCall(
        address simulatedCaller,
        uint256 _dstChainId,
        address _target,
        bytes memory _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address _refundAddress,
        uint256[] memory _fees,
        uint256 _successThreshold,
        address[] memory _excludedAdapters
    ) external prank(simulatedCaller) {
        multiBridgeMessageSender.remoteCall(
            _dstChainId,
            _target,
            _callData,
            _nativeValue,
            _expiration,
            _refundAddress,
            _fees,
            _successThreshold,
            _excludedAdapters
        );
    }
}
