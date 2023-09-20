// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @notice interface for GAC (Global Access Controller)
interface IGAC {
    /*///////////////////////////////////////////////////////////////
                            EVENT
    //////////////////////////////////////////////////////////////*/
    event MultiMessageReceiverUpdated(uint256 chainId, address indexed mmaReceiver);

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev sets the multi message contracts
    /// @param _chainId is the unique chain identifier of the receiver address
    /// @param _mmaReceiver is the multi message receiver contracts
    function setMultiMessageReceiver(uint256 _chainId, address _mmaReceiver) external;

    /*///////////////////////////////////////////////////////////////
                    EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev returns `true` if the caller is global access controller
    /// @param _caller is the msg.sender to validate
    /// @return boolean indicating the validity of the caller
    function isGlobalOwner(address _caller) external view returns (bool);

    /// @dev returns the global owner address
    /// @return _owner is the global owner address
    function getGlobalOwner() external view returns (address _owner);

    /// @dev returns the multi message receiver on the chain
    function getMultiMessageReceiver(uint256 _chainId) external view returns (address _mmaReceiver);
}
