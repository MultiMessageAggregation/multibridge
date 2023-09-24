// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @notice interface for GAC (Global Access Controller)
interface IGAC {
    /// @notice Checks whether a given address is the global owner
    /// @param _addr is the address to compare with the global owner
    /// @return boolean true if _caller is the global owner, false otherwise
    function isGlobalOwner(address _addr) external view returns (bool);

    /// @notice returns the global owner address.
    /// @return _owner is the global owner address
    function getGlobalOwner() external view returns (address _owner);
}
