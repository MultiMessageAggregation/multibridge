// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// external modules
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// interfaces
import "./interfaces/IMultiMessageReceiver.sol";
import "./interfaces/EIP5164/ExecutorAware.sol";

/// libraries
import "./libraries/Error.sol";
import "./libraries/Message.sol";

/// @title MultiMessageReceiver
/// @dev receives message from bridge adapters
contract MultiMessageReceiver is IMultiMessageReceiver, ExecutorAware, Initializable {
    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @notice minimum number of AMBs required for delivery before execution
    uint64 public quorumThreshold;

    struct ExecutionData {
        address target;
        bytes callData;
        uint256 nonce;
        uint256 expiration;
    }

    /// @notice stores each msg id related info
    mapping(bytes32 => bool) public isExecuted;
    mapping(bytes32 => ExecutionData) public msgReceived;
    mapping(bytes32 => mapping(address => bool)) public isDuplicateAdapter;
    mapping(bytes32 => uint256) public quorum;
    mapping(bytes32 => string[]) public successfulBridges;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    event ReceiverAdapterUpdated(address receiverAdapter, bool add);
    event QuorumThresholdUpdated(uint64 quorumThreshold);
    event SingleBridgeMsgReceived(bytes32 msgId, string indexed bridgeName, uint256 nonce, address receiverAdapter);
    event MessageExecuted(bytes32 msgId, address target, uint256 nonce, bytes callData);

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @notice A modifier used for restricting the caller of some functions to be configured receiver adapters.
    modifier onlyReceiverAdapter() {
        if (!isTrustedExecutor(msg.sender)) {
            revert Error.INVALID_RECEIVER_ADAPTER();
        }
        _;
    }

    ///  @notice A modifier used for restricting the caller of some functions to be this contract itself.
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Error.INVALID_SELF_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                INITIALIZER
    ////////////////////////////////////////////////////////////////*/

    /// @notice sets the initial paramters
    function initialize(address[] calldata _receiverAdapters, uint64 _quorumThreshold) external initializer {
        uint256 len = _receiverAdapters.length;

        if (len == 0) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        for (uint256 i; i < len;) {
            if (_receiverAdapters[i] == address(0)) {
                revert Error.ZERO_ADDRESS_INPUT();
            }

            _updateReceiverAdapter(_receiverAdapters[i], true);

            unchecked {
                ++i;
            }
        }

        if (_quorumThreshold > trustedExecutor.length) {
            revert Error.INVALID_QUORUM_THRESHOLD();
        }

        quorumThreshold = _quorumThreshold;
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Receive messages from allowed bridge receiver adapters.
    /// @dev If the accumulated power of a message has reached the power threshold,
    /// this message will be executed immediately, which will invoke an external function call
    /// according to the message content.
    function receiveMessage(MessageLibrary.Message calldata _message, uint256 _srcChainId)
        external
        override
        onlyReceiverAdapter
    {
        if (_message.dstChainId != block.chainid) {
            revert Error.INVALID_DST_CHAIN();
        }

        /// This msgId is totally different with each adapters' internal msgId(which is their internal nonce essentially)
        /// Although each adapters' internal msgId is attached at the end of calldata, it's not useful to MultiMessageReceiver.
        bytes32 msgId = MessageLibrary.computeMsgId(_message, uint64(_srcChainId));

        if (isDuplicateAdapter[msgId][msg.sender]) {
            revert Error.DUPLICATE_MESSAGE_DELIVERY_BY_ADAPTER();
        }

        if (isExecuted[msgId]) {
            revert Error.MSG_ID_ALREADY_EXECUTED();
        }

        /// increment quorum
        isDuplicateAdapter[msgId][msg.sender] = true;
        ++quorum[msgId];

        /// stores the execution data required
        ExecutionData memory prevStored = msgReceived[msgId];
        if (prevStored.target != address(0)) {
            if (
                prevStored.target != _message.target || keccak256(prevStored.callData) != keccak256(_message.callData)
                    || prevStored.expiration != _message.expiration || prevStored.nonce != _message.nonce
            ) {
                revert Error.NEW_MESSAGE_CONFLITS_WITH_OLD_DATA();
            }
        } else {
            msgReceived[msgId] = ExecutionData(_message.target, _message.callData, _message.nonce, _message.expiration);
        }

        successfulBridges[msgId].push(_message.bridgeName);

        emit SingleBridgeMsgReceived(msgId, _message.bridgeName, _message.nonce, msg.sender);
    }

    /// @notice Execute the message (invoke external call according to the message content) if the message
    /// @dev has reached the power threshold (the same message has been delivered by enough multiple bridges).
    /// Param values can be found in the MultiMessageMsgSent event from the source chain MultiMessageSender contract.
    function executeMessage(bytes32 msgId) external {
        ExecutionData memory _execData = msgReceived[msgId];

        if (block.timestamp > _execData.expiration) {
            revert Error.MSG_EXECUTION_PASSED_DEADLINE();
        }

        if (isExecuted[msgId]) {
            revert Error.MSG_ID_ALREADY_EXECUTED();
        }

        isExecuted[msgId] = true;

        if (quorum[msgId] < quorumThreshold) {
            revert Error.INVALID_QUORUM_FOR_EXECUTION();
        }

        (bool status,) = _execData.target.call(_execData.callData);

        if (!status) {
            revert Error.EXECUTION_FAILS_ON_DST();
        }

        emit MessageExecuted(msgId, _execData.target, _execData.nonce, _execData.callData);
    }

    /// @notice Update bridge receiver adapters.
    /// @dev called by admin to update receiver bridge adapters on all other chains
    function updateReceiverAdapter(address[] calldata _receiverAdapters, bool[] calldata _operations)
        external
        onlySelf
    {
        uint256 len = _receiverAdapters.length;

        if(len != _operations.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }
        
        for (uint256 i; i < len; ) {
            _updateReceiverAdapter(_receiverAdapters[i], _operations[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Update power quorum threshold of message execution.
    function updateQuorumThreshold(uint64 _quorumThreshold) external onlySelf {
        /// NOTE: should check 2/3 ?
        if(_quorumThreshold <= trustedExecutor.length || _quorumThreshold == 0) {
            revert Error.INVALID_QUORUM_THRESHOLD();
        }
        
        quorumThreshold = _quorumThreshold;
        emit QuorumThresholdUpdated(_quorumThreshold);
    }

    /// @notice view message info, return (executed, msgPower, delivered adapters)
    function getMessageInfo(bytes32 msgId) public view returns (bool, uint256, string[] memory) {
        return (isExecuted[msgId], quorum[msgId], successfulBridges[msgId]);
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _updateReceiverAdapter(address _receiverAdapter, bool _add) private {
        if (_add) {
            _addTrustedExecutor(_receiverAdapter);
        } else {
            _removeTrustedExecutor(_receiverAdapter);

            if (quorumThreshold > trustedExecutor.length) {
                revert Error.INVALID_QUORUM_THRESHOLD();
            }
        }
        emit ReceiverAdapterUpdated(_receiverAdapter, _add);
    }
}
