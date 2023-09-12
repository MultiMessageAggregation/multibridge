// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// library imports
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// local imports
import {IGAC} from "../interfaces/IGAC.sol";
import {Error} from "../libraries/Error.sol";

/// @dev is the global access control contract for bridge adapters
contract GAC is IGAC, Ownable {
    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MINIMUM_DST_GAS_LIMIT = 50000;

    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public dstGasLimit;

    /// @dev is the address to receive value refunds from remoteCall
    address public refundAddress;

    /// @notice is the MMA Core Contracts on the chain
    /// @dev leveraged by bridge adapters for authentication
    address public multiMessageSender;

    /// @dev is the allowed caller for the multi-message sender
    address public allowedCaller;

    mapping(uint256 chainId => address mmaReceiver) public multiMessageReceiver;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable() {}

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGAC
    function setMultiMessageSender(address _mmaSender) external override onlyOwner {
        if (_mmaSender == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        multiMessageSender = _mmaSender;

        emit MultiMessageSenderUpdated(_mmaSender);
    }

    /// @inheritdoc IGAC
    function setMultiMessageCaller(address _mmaCaller) external override onlyOwner {
        if (_mmaCaller == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        allowedCaller = _mmaCaller;

        emit MultiMessageCallerUpdated(_mmaCaller);
    }

    /// @inheritdoc IGAC
    function setMultiMessageReceiver(uint256 _chainId, address _mmaReceiver) external override onlyOwner {
        if (_mmaReceiver == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        if (_chainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        multiMessageReceiver[_chainId] = _mmaReceiver;

        emit MultiMessageReceiverUpdated(_chainId, _mmaReceiver);
    }

    /// @inheritdoc IGAC
    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external override onlyOwner {
        if (_gasLimit < MINIMUM_DST_GAS_LIMIT) {
            revert Error.INVALID_DST_GAS_LIMIT_MIN();
        }

        uint256 oldLimit = dstGasLimit;
        dstGasLimit = _gasLimit;

        emit DstGasLimitUpdated(oldLimit, _gasLimit);
    }

    /// @inheritdoc IGAC
    function setRefundAddress(address _refundAddress) external override onlyOwner {
        if (_refundAddress == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        refundAddress = _refundAddress;
    }

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGAC
    function isGlobalOwner(address _caller) external view override returns (bool) {
        if (_caller == owner()) {
            return true;
        }

        return false;
    }

    /// @inheritdoc IGAC
    function getGlobalOwner() external view override returns (address _owner) {
        _owner = owner();
    }

    /// @inheritdoc IGAC
    function getGlobalMsgDeliveryGasLimit() external view override returns (uint256 _gasLimit) {
        _gasLimit = dstGasLimit;
    }

    /// @inheritdoc IGAC
    function getRefundAddress() external view override returns (address _refundAddress) {
        _refundAddress = refundAddress;
    }

    /// @inheritdoc IGAC
    function getMultiMessageSender() external view returns (address _mmaSender) {
        _mmaSender = multiMessageSender;
    }

    /// @inheritdoc IGAC
    function getMultiMessageReceiver(uint256 _chainId) external view returns (address _mmaReceiver) {
        _mmaReceiver = multiMessageReceiver[_chainId];
    }

    /// @inheritdoc IGAC
    function getMultiMessageCaller() external view returns (address _mmaCaller) {
        _mmaCaller = allowedCaller;
    }
}
