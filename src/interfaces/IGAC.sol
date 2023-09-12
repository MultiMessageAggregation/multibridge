// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// @notice interface for GAC (Global Access Controller)
interface IGAC {
    /*///////////////////////////////////////////////////////////////
                            EVENT
    //////////////////////////////////////////////////////////////*/
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);

    event MultiMessageCallerUpdated(address indexed mmaCaller);

    event MultiMessageSenderUpdated(address indexed mmaSender);

    event MultiMessageReceiverUpdated(uint256 chainId, address indexed mmaReceiver);

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev sets the multi message sender caller
    /// @param _mmaCaller is the multi message caller
    function setMultiMessageCaller(address _mmaCaller) external;

    /// @dev sets the multi message sender on same chain
    /// @param _mmaSender is the multi message sender contracts
    function setMultiMessageSender(address _mmaSender) external;

    /// @dev sets the multi message contracts
    /// @param _chainId is the unique chain identifier of the receiver address
    /// @param _mmaReceiver is the multi message receiver contracts
    function setMultiMessageReceiver(uint256 _chainId, address _mmaReceiver) external;

    /// @dev sets the global message gas limits
    /// @param _gasLimit is the limit to be set
    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external;

    /// @dev sets the refund address for gas refunds
    /// @param _refundAddress is the address to receive refunds from MMA sender
    function setRefundAddress(address _refundAddress) external;

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

    /// @dev returns the global message delivery gas limit configured
    /// @return _gasLimit is the configured gas limit on dst
    function getGlobalMsgDeliveryGasLimit() external view returns (uint256 _gasLimit);

    /// @dev returns the multi message sender on the chain
    function getMultiMessageSender() external view returns (address _mmaSender);

    /// @dev returns the multi message caller that can only call the multi message sender contract
    function getMultiMessageCaller() external view returns (address _mmaCaller);

    /// @dev returns the multi message receiver on the chain
    function getMultiMessageReceiver(uint256 _chainId) external view returns (address _mmaReceiver);

    /// @dev returns the refund address
    function getRefundAddress() external view returns (address _refundAddress);
}
