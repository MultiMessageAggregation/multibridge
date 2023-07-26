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
    uint256 public senderChainId;

    /// @dev trakcs the msg id status to prevent replay attacks
    mapping(bytes32 => bool) public isMessageExecuted;
    mapping(bytes32 => bool) public deBridgeisMessageExecuted;

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
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external override onlyCaller {
        uint256 _senderChainDecoded = abi.decode(_senderChain, (uint256));

        if (_senderChainDecoded == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;
        senderChainId = _senderChainDecoded;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter, _senderChain);
    }

    /// @dev accepts incoming messages from debridge gate
    function executeMessage(address _srcSender, address, bytes calldata _data, bytes32 _msgId) external {
        ICallProxy callProxy = ICallProxy(deBridgeGate.callProxy());
        uint256 submissionChainIdFrom = callProxy.submissionChainIdFrom();

        /// @dev step-1: validate incoming chain id
        if (submissionChainIdFrom != senderChainId) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the caller
        if (msg.sender != address(callProxy)) {
            revert Error.NOT_APPROVED_BY_GATEWAY();
        }

        /// @dev step-3: validate the source address
        if (_srcSender != senderAdapter) {
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(_data, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-4: check for duplicate message
        if (deBridgeisMessageExecuted[_msgId] || isMessageExecuted[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        /// @dev step-5: validate the destination
        if (decodedPayload.finalDestination != gac.getMultiMessageReceiver()) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        isMessageExecuted[msgId] = true;
        deBridgeisMessageExecuted[_msgId] = true;

        // (bool ok, bytes memory lowLevelData) =
        //     _destReceiver.call(abi.encodePacked(_data, _msgId, submissionChainIdFrom, _srcSender));

        // if (!ok) {
        //     revert MessageFailure(_msgId, lowLevelData);
        // } else {
        //     emit MessageIdExecuted(submissionChainIdFrom, _msgId);
        // }
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
