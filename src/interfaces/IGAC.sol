// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @notice interface for GAC (Global Access Controller)
interface IGAC {
    /*///////////////////////////////////////////////////////////////
                            EVENT
    //////////////////////////////////////////////////////////////*/
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);

    event CoreContractsUpdated(address indexed mmaSender, address indexed mmaReceiver);

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev sets the multi message contracts
    /// @param _mmaSender is the multi message sender contracts
    /// @param _mmaReceiver is the multi message receiver contracts
    function setMultiMessageCoreContracts(address _mmaSender, address _mmaReceiver) external;

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

    /// @dev returns the multi message sender on the chain
    function getMultiMessageSender() external view returns (address _mmaSender);

    /// @dev returns the multi message receiver on the chain
    function getMultiMessageReceiver() external view returns (address _mmaReceiver);
}
