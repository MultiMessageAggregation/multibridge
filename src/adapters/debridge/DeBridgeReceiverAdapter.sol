// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../libraries/Error.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Types.sol";

import "./interfaces/IDeBridgeReceiverAdapter.sol";
import "./interfaces/IDeBridgeGate.sol";
import "./interfaces/ICallProxy.sol";

/// @notice sender adapter for de-bridge
contract DeBridgeReceiverAdapter is IDeBridgeReceiverAdapter, IBridgeReceiverAdapter {
    IDeBridgeGate public immutable deBridgeGate;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev adapter deployed to Ethereum
    address public senderAdapter;

    /// @dev trakcs the msg id status to prevent replay attacks
    mapping(bytes32 => bool) public executedMessages;

    /* ========== ERRORS ========== */

    error CallProxyBadRole();
    error NativeSenderBadRole(address nativeSender, uint256 chainIdFrom);

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _deBridgeGate, address _gac) {
        deBridgeGate = IDeBridgeGate(_deBridgeGate);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    /// @dev accepts incoming messages from debridge gate
    function executeMessage(address _srcSender, address _destReceiver, bytes calldata _data, bytes32 _msgId) external {
        ICallProxy callProxy = ICallProxy(deBridgeGate.callProxy());

        if (msg.sender != address(callProxy)) {
            revert Error.CALLER_NOT_DEBRIDGE_GATE();
        }

        address nativeSender = _toAddress(callProxy.submissionNativeSender(), 0);
        uint256 submissionChainIdFrom = callProxy.submissionChainIdFrom();

        if (senderAdapter != nativeSender) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        if (executedMessages[_msgId]) {
            revert MessageIdAlreadyExecuted(_msgId);
        }

        executedMessages[_msgId] = true;

        (bool ok, bytes memory lowLevelData) =
            _destReceiver.call(abi.encodePacked(_data, _msgId, submissionChainIdFrom, _srcSender));

        if (!ok) {
            revert MessageFailure(_msgId, lowLevelData);
        } else {
            emit MessageIdExecuted(submissionChainIdFrom, _msgId);
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }
}
