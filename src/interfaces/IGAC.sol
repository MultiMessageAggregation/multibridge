// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @notice interface for GAC (Global Access Controller)
interface IGAC {
    /*///////////////////////////////////////////////////////////////
                            EVENT
    //////////////////////////////////////////////////////////////*/
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev sets the global message gas limits
    /// @param _gasLimit is the limit to be set
    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external;

    /*///////////////////////////////////////////////////////////////
                    EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev returns `true` if the caller is global access controller
    /// @param _caller is the msg.sender to validate
    /// @return boolean indicating the validity of the caller
    function isPrevilagedCaller(address _caller) external view returns (bool);

    /// @dev returns the global message delivery gas limit configured
    /// @return _gasLimit is the configured gas limit on dst
    function getGlobalMsgDeliveryGasLimit() external view returns (uint256 _gasLimit);
}
