// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// library imports
import "openzeppelin-contracts/contracts/access/Ownable.sol";

import {Error} from "../libraries/Error.sol";
import {GAC} from "./GAC.sol";

contract MessageSenderGAC is GAC {
    /*///////////////////////////////////////////////////////////////
                            EVENT
    //////////////////////////////////////////////////////////////*/
    event DstGasLimitUpdated(uint256 oldLimit, uint256 newLimit);

    event MultiBridgeMessageCallerUpdated(address indexed mmaCaller);

    event MultiBridgeMessageSenderUpdated(address indexed mmaSender);

    event MultiBridgeMessageReceiverUpdated(uint256 indexed chainId, address indexed oldMMR, address indexed newMMR);

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
    address public multiBridgeMessageSender;

    /// @dev is the authorised caller for the multi-message sender
    address public authorisedCaller;

    mapping(uint256 chainId => address mmaReceiver) public remoteMultiBridgeMessageReceiver;

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setMultiBridgeMessageSender(address _mmaSender) external onlyOwner {
        if (_mmaSender == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        multiBridgeMessageSender = _mmaSender;

        emit MultiBridgeMessageSenderUpdated(_mmaSender);
    }

    function setAuthorisedCaller(address newMMSCaller) external onlyOwner {
        if (newMMSCaller == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        authorisedCaller = newMMSCaller;

        emit MultiBridgeMessageCallerUpdated(newMMSCaller);
    }

    function setRemoteMultiBridgeMessageReceiver(uint256 _chainId, address _remoteMMR) external onlyOwner {
        if (_remoteMMR == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        if (_chainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        address oldRemoteMMR = remoteMultiBridgeMessageReceiver[_chainId];
        remoteMultiBridgeMessageReceiver[_chainId] = _remoteMMR;

        emit MultiBridgeMessageReceiverUpdated(_chainId, oldRemoteMMR, _remoteMMR);
    }

    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external onlyOwner {
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

    function getGlobalMsgDeliveryGasLimit() external view returns (uint256 _gasLimit) {
        _gasLimit = dstGasLimit;
    }

    function getMultiBridgeMessageSender() external view returns (address _mmaSender) {
        _mmaSender = multiBridgeMessageSender;
    }

    function getRemoteMultiBridgeMessageReceiver(uint256 _chainId) external view returns (address _mmaReceiver) {
        _mmaReceiver = remoteMultiBridgeMessageReceiver[_chainId];
    }

    function getAuthorisedCaller() external view returns (address _mmaCaller) {
        _mmaCaller = authorisedCaller;
    }
}
