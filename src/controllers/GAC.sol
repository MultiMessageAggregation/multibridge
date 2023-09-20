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
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 chainId => address mmaReceiver) public multiMessageReceiver;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable() {}

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
    function getMultiMessageReceiver(uint256 _chainId) external view returns (address _mmaReceiver) {
        _mmaReceiver = multiMessageReceiver[_chainId];
    }
}
