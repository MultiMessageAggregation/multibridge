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

    /// @dev tracks the msg id status to prevent replay
    mapping(bytes32 => bool) public executedMessages;

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
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    /// @dev accepts incoming messages from telepathy router
    function handleTelepathy(uint32 _srcChainId, address _srcAddress, bytes memory _message)
        external
        onlyRouterContract
        returns (bytes4)
    {
        AdapterPayload memory decodedPayload = abi.decode(_message, (AdapterPayload));

        if (_srcAddress != senderAdapter) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        if (executedMessages[decodedPayload.msgId]) {
            revert MessageIdAlreadyExecuted(decodedPayload.msgId);
        }

        executedMessages[decodedPayload.msgId] = true;

        /// @dev send message to destReceiver
        (bool success, bytes memory lowLevelData) = decodedPayload.finalDestination.call(
            abi.encodePacked(
                decodedPayload.data, decodedPayload.msgId, uint256(_srcChainId), decodedPayload.senderAdapterCaller
            )
        );

        if (!success) {
            revert MessageFailure(decodedPayload.msgId, lowLevelData);
        }

        emit MessageIdExecuted(uint256(_srcChainId), decodedPayload.msgId);
        return ITelepathyHandler.handleTelepathy.selector;
    }
}
