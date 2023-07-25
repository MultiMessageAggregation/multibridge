// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./libraries/Utils.sol";

interface IMessageReceiverApp {
    enum ExecutionStatus {
        Fail, // execution failed, finalized
        Success, // execution succeeded, finalized
        Retry // execution rejected, can retry later
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
    string constant ABORT_PREFIX = "MSG::ABORT:";

    address public immutable msgBus;
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

    modifier onlyMessageBus() {
        require(msg.sender == msgBus, "caller is not message bus");
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
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    /// @dev accepts incoming messages from celer message bus
    function executeMessage(
        address _srcContract,
        uint64 _srcChainId,
        bytes calldata _message,
        address // executor
    ) external payable override onlyMessageBus returns (ExecutionStatus) {
        AdapterPayload memory decodedPayload = abi.decode(_message, (AdapterPayload));

        if (_srcContract != senderAdapter) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        if (executedMessages[decodedPayload.msgId]) {
            revert MessageIdAlreadyExecuted(decodedPayload.msgId);
        }

        executedMessages[decodedPayload.msgId] = true;

        (bool ok, bytes memory lowLevelData) = decodedPayload.finalDestination.call(
            abi.encodePacked(
                decodedPayload.data, decodedPayload.msgId, uint256(_srcChainId), decodedPayload.senderAdapterCaller
            )
        );

        if (!ok) {
            string memory reason = Utils.getRevertMsg(lowLevelData);
            revert(
                string.concat(
                    ABORT_PREFIX,
                    string(abi.encodeWithSelector(MessageFailure.selector, decodedPayload.msgId, bytes(reason)))
                )
            );
        } else {
            emit MessageIdExecuted(uint256(_srcChainId), decodedPayload.msgId);
            return ExecutionStatus.Success;
        }
    }
}
