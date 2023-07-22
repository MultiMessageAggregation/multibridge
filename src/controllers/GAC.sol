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

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable() {}

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
}
