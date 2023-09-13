// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IMultiMessageReceiver.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../../libraries/Message.sol";

import "./libraries/Utils.sol";

interface IMessageReceiverApp {
    enum ExecutionStatus {
        Success // execution succeeded, finalized
    }

    /// @notice Called by MessageBus to execute a message
    /// @param _sender The address of the source app contract
    /// @param _srcChainId The source chain ID where the transfer is originated from
    /// @param _message Arbitrary message bytes originated from and encoded by the source app contract
    /// @param _executor Address who called the MessageBus execution function
    function executeMessage(address _sender, uint64 _srcChainId, bytes calldata _message, address _executor)
        external
        payable
        returns (ExecutionStatus);
}

contract CelerReceiverAdapter is IBridgeReceiverAdapter, IMessageReceiverApp {
    string public constant name = "celer";
    address public immutable msgBus;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev adapter deployed to Ethereum
    address public senderAdapter;
    uint64 public senderChain;

    /// @dev tracks the msg id status to prevent replay
    mapping(bytes32 => bool) public isMessageExecuted;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyGlobalOwner() {
        if (!gac.isGlobalOwner(msg.sender)) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    modifier onlyMessageBus() {
        if (msg.sender == msgBus) {
            revert Error.CALLER_NOT_CELER_BUS();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _msgBus, address _gac) {
        msgBus = _msgBus;
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external override onlyGlobalOwner {
        uint64 _senderChainDecoded = abi.decode(_senderChain, (uint64));

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

    /// @dev accepts incoming messages from celer message bus
    function executeMessage(
        address _srcContract,
        uint64 _srcChainId,
        bytes calldata _message,
        address // executor
    ) external payable override onlyMessageBus returns (ExecutionStatus) {
        /// @dev validate the caller (done in modifier)
        /// @dev step-1: validate incoming chain id
        if (_srcChainId != senderChain) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the source address
        if (_srcContract != senderAdapter) {
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(_message, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-3: check for duplicate message
        if (isMessageExecuted[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        isMessageExecuted[decodedPayload.msgId] = true;

        /// @dev step-4: validate the destination
        if (decodedPayload.finalDestination != gac.getMultiMessageReceiver(block.chainid)) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        MessageLibrary.Message memory _data = abi.decode(decodedPayload.data, (MessageLibrary.Message));

        try IMultiMessageReceiver(decodedPayload.finalDestination).receiveMessage(_data, name) {
            emit MessageIdExecuted(_data.srcChainId, msgId);
        } catch (bytes memory lowLevelData) {
            revert MessageFailure(msgId, lowLevelData);
        }

        return ExecutionStatus.Success;
    }
}
