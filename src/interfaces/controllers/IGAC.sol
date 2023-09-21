// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @notice interface for GAC (Global Access Controller)
interface IGAC {
    /// @dev returns `true` if the caller is global access controller
    /// @param _caller is the msg.sender to validate
    /// @return boolean indicating the validity of the caller
    function isGlobalOwner(address _caller) external view returns (bool);

    /// @dev returns the global owner address
    /// @return _owner is the global owner address
    function getGlobalOwner() external view returns (address _owner);
}
