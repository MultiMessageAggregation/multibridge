// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/ITelepathy.sol";

/// @notice receiver adapter for telepathy bridge
contract TelepathyReceiverAdapter is IBridgeReceiverAdapter, ITelepathyHandler {
    ITelepathyRouter public immutable telepathyRouter;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    /// @dev adapter deployed to Ethereum
    address public senderAdapter;
    uint32 public senderChain;

    /// @dev tracks the msg id status to prevent replay
    mapping(bytes32 => bool) public isMessageExecuted;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    modifier onlyRouterContract() {
        if (msg.sender != address(telepathyRouter)) {
            revert Error.CALLER_NOT_TELEPATHY_ROUTER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _telepathyRouter, address _gac) {
        telepathyRouter = ITelepathyRouter(_telepathyRouter);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external override onlyCaller {
        uint32 _senderChainDecoded = abi.decode(_senderChain, (uint32));

        if (_senderChainDecoded == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;
        senderChain = _senderChainDecoded;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter, _senderChain);
    }

    /// @dev accepts incoming messages from telepathy router
    function handleTelepathy(uint32 _srcChainId, address _srcAddress, bytes memory _message)
        external
        onlyRouterContract
        returns (bytes4)
    {
        /// @dev step-1: validate incoming chain id
        if (_srcChainId != senderChain) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the caller (done in modifier)

        /// @dev step-3: validate the source address
        if (_srcAddress != senderAdapter) {
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(_message, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-4: check for duplicate message
        if (isMessageExecuted[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        isMessageExecuted[decodedPayload.msgId] = true;

        /// @dev step-5: validate the destination
        if (decodedPayload.finalDestination != gac.getMultiMessageReceiver()) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        /// @dev send message to destReceiver
        // (bool success, bytes memory lowLevelData) = decodedPayload.finalDestination.call(
        //     abi.encodePacked(
        //         decodedPayload.data, decodedPayload.msgId, uint256(_srcChainId), decodedPayload.senderAdapterCaller
        //     )
        // );

        // if (!success) {
        //     revert MessageFailure(decodedPayload.msgId, lowLevelData);
        // }

        // emit MessageIdExecuted(uint256(_srcChainId), decodedPayload.msgId);
        return ITelepathyHandler.handleTelepathy.selector;
    }
}
