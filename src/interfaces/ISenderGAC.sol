// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import {IGAC} from "./IGAC.sol";

/// @notice interface for GAC (Global Access Controller) on sender chain
interface ISenderGAC is IGAC {
    /*///////////////////////////////////////////////////////////////
                            EVENT
    //////////////////////////////////////////////////////////////*/
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);

    event MultiMessageCallerUpdated(address indexed mmaCaller);

    event MultiMessageSenderUpdated(address indexed mmaSender);

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev sets the multi message sender caller
    /// @param _mmaCaller is the multi message caller
    function setMultiMessageCaller(address _mmaCaller) external;

    /// @dev sets the multi message sender on same chain
    /// @param _mmaSender is the multi message sender contracts
    function setMultiMessageSender(address _mmaSender) external;

    /// @dev sets the global message gas limits
    /// @param _gasLimit is the limit to be set
    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external;

    /*///////////////////////////////////////////////////////////////
                    EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev returns the global message delivery gas limit configured
    /// @return _gasLimit is the configured gas limit on dst
    function getGlobalMsgDeliveryGasLimit() external view returns (uint256 _gasLimit);

    /// @dev returns the multi message sender on the chain
    function getMultiMessageSender() external view returns (address _mmaSender);

    /// @dev returns the multi message caller that can only call the multi message sender contract
    function getMultiMessageCaller() external view returns (address _mmaCaller);
}
