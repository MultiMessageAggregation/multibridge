// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "forge-std/Test.sol";

/// library imports
import {MessageSenderGAC} from "src/controllers/MessageSenderGAC.sol";
import {MultiBridgeMessageSender} from "src/MultiBridgeMessageSender.sol";

/// @notice handler for testing maintaining adapter list
contract AdapterListHandler is Test {
    /// @notice local state
    MultiBridgeMessageSender public multiBridgeMessageSender;
    MessageSenderGAC public gac;

    bool public success;
    uint256 public currAdds;

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

    /// @notice helper for adding new adapters
    function addSenderAdapters(address _newSenderAdapter) external prank(gac.getGlobalOwner()) {
        success = false;

        vm.assume(_newSenderAdapter != address(0));

        address[] memory _additions = new address[](1);
        _additions[0] = _newSenderAdapter;

        try multiBridgeMessageSender.addSenderAdapters(_additions) {
            success = true;
            currAdds++;
        } catch {}
    }

    /// @notice helper for removing existing adapters
    function removeSenderAdapters() external prank(gac.getGlobalOwner()) {
        vm.assume(currAdds > 0);
        success = false;

        address[] memory _removals = new address[](1);
        _removals[0] = multiBridgeMessageSender.senderAdapters(currAdds - 1);

        try multiBridgeMessageSender.removeSenderAdapters(_removals) {
            success = true;
            currAdds--;
        } catch {}
    }
}
