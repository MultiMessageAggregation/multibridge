// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import {GAC} from "./GAC.sol";
import {Error} from "../libraries/Error.sol";
import {ISenderGAC} from "../interfaces/ISenderGAC.sol";

/// @dev is extension of GAC containing sender only functions
contract SenderGAC is GAC, ISenderGAC {
    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MINIMUM_DST_GAS_LIMIT = 50000;

    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public dstGasLimit;

    /// @notice is the MMA Core Contracts on the chain
    /// @dev leveraged by bridge adapters for authentication
    address public multiMessageSender;

    /// @dev is the allowed caller for the multi-message sender
    address public allowedCaller;

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISenderGAC
    function setMultiMessageSender(address _mmaSender) external override onlyOwner {
        if (_mmaSender == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        multiMessageSender = _mmaSender;

        emit MultiMessageSenderUpdated(_mmaSender);
    }

    /// @inheritdoc ISenderGAC
    function setMultiMessageCaller(address _mmaCaller) external override onlyOwner {
        if (_mmaCaller == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        allowedCaller = _mmaCaller;

        emit MultiMessageCallerUpdated(_mmaCaller);
    }

    /// @inheritdoc ISenderGAC
    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external override onlyOwner {
        if (_gasLimit < MINIMUM_DST_GAS_LIMIT) {
            revert Error.INVALID_DST_GAS_LIMIT_MIN();
        }

        uint256 oldLimit = dstGasLimit;
        dstGasLimit = _gasLimit;

        emit DstGasLimitUpdated(oldLimit, _gasLimit);
    }
    /*///////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISenderGAC
    function getMultiMessageCaller() external view returns (address _mmaCaller) {
        _mmaCaller = allowedCaller;
    }

    /// @inheritdoc ISenderGAC
    function getMultiMessageSender() external view returns (address _mmaSender) {
        _mmaSender = multiMessageSender;
    }

    /// @inheritdoc ISenderGAC
    function getGlobalMsgDeliveryGasLimit() external view override returns (uint256 _gasLimit) {
        _gasLimit = dstGasLimit;
    }
}
