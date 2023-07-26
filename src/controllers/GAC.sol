// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// library imports
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/// local imports
import {IGAC} from "../interfaces/IGAC.sol";

/// @dev is the global access control contract for bridge adapters
contract GAC is IGAC, Ownable {
    /*///////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public dstGasLimit;

    /// @notice is the MMA Core Contracts on the chain
    /// @dev leveraged by bridge adapters for authentication
    address public multiMessageSender;
    address public multiMessageReceiver;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable() {}

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGAC
    function setMultiMessageCoreContracts(address _mmaSender, address _mmaReceiver) external override onlyOwner {
        multiMessageSender = _mmaSender;
        multiMessageReceiver = _mmaReceiver;

        emit CoreContractsUpdated(_mmaSender, _mmaReceiver);
    }

    /// @inheritdoc IGAC
    function setGlobalMsgDeliveryGasLimit(uint256 _gasLimit) external override onlyOwner {
        uint256 oldLimit = dstGasLimit;
        dstGasLimit = _gasLimit;

        emit DstGasLimitUpdated(oldLimit, _gasLimit);
    }

    /*///////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGAC
    function isPrevilagedCaller(address _caller) external view override returns (bool) {
        if (_caller == owner()) {
            return true;
        }

        return false;
    }

    /// @inheritdoc IGAC
    function getGlobalMsgDeliveryGasLimit() external view override returns (uint256 _gasLimit) {
        _gasLimit = dstGasLimit;
    }

    /// @inheritdoc IGAC
    function getMultiMessageSender() external view returns (address _mmaSender) {
        _mmaSender = multiMessageSender;
    }

    /// @inheritdoc IGAC
    function getMultiMessageReceiver() external view returns (address _mmaReceiver) {
        _mmaReceiver = multiMessageReceiver;
    }
}
