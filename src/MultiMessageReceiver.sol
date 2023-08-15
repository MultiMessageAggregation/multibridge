// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// external modules
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// interfaces
import "./interfaces/IBridgeReceiverAdapter.sol";
import "./interfaces/IMultiMessageReceiver.sol";
import "./interfaces/EIP5164/ExecutorAware.sol";
import "./interfaces/IGAC.sol";

/// libraries
import "./libraries/Error.sol";
import "./libraries/Message.sol";

/// @title MultiMessageReceiver
/// @dev receives message from bridge adapters
contract MultiMessageReceiver is IMultiMessageReceiver, ExecutorAware, Initializable {
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @notice minimum number of AMBs required for delivery before execution
    uint64 public quorum;

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
    mapping(bytes32 => uint256) public messageVotes;
    mapping(bytes32 => uint256) public deliveryTime;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    event ReceiverAdapterUpdated(address receiverAdapter, bool add);
    event quorumUpdated(uint64 oldValue, uint64 newValue);
    event SingleBridgeMsgReceived(
        bytes32 indexed msgId, string indexed bridgeName, uint256 nonce, address receiverAdapter
    );
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

    /// @notice A modifier used for restricting the caller of some functions to be this contract itself.
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Error.INVALID_SELF_CALLER();
        }
        _;
    }
    
    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _gac is the controller/registry of uniswap mma
    constructor(address _gac) {
        if (_gac == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                                INITIALIZER
    ////////////////////////////////////////////////////////////////*/

    /// @notice sets the initial paramters
    function initialize(address[] calldata _receiverAdapters, uint64 _quorum) external initializer {
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

        if (_quorum > trustedExecutor.length || _quorum == 0) {
            revert Error.INVALID_QUORUM_THRESHOLD();
        }

        quorum = _quorum;
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice receive messages from allowed bridge receiver adapters
    /// @param _message is the crosschain message sent by the mma sender
    /// @param _bridgeName is the name of the bridge the relays the message
    function receiveMessage(MessageLibrary.Message calldata _message, string memory _bridgeName)
        external
        override
        onlyReceiverAdapter
    {
        if (_message.dstChainId != block.chainid) {
            revert Error.INVALID_DST_CHAIN();
        }

        /// FIXME: could make this configurable through GAC, instead of hardcoding 1
        if (_message.srcChainId != 1) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// this msgId is totally different with each adapters' internal msgId(which is their internal nonce essentially)
        /// although each adapters' internal msgId is attached at the end of calldata, it's not useful to MultiMessageReceiver.
        bytes32 msgId = MessageLibrary.computeMsgId(_message);

        if (isDuplicateAdapter[msgId][msg.sender]) {
            revert Error.DUPLICATE_MESSAGE_DELIVERY_BY_ADAPTER();
        }

        if (isExecuted[msgId]) {
            revert Error.MSG_ID_ALREADY_EXECUTED();
        }

        isDuplicateAdapter[msgId][msg.sender] = true;

        /// increment quorum
        ++messageVotes[msgId];

        /// stores the delivery time
        deliveryTime[msgId] = block.timestamp;

        /// stores the execution data required
        ExecutionData memory prevStored = msgReceived[msgId];

        /// stores the message if the amb is the first one delivering the message
        if (prevStored.target == address(0)) {
            msgReceived[msgId] = ExecutionData(_message.target, _message.callData, _message.nonce, _message.expiration);
        }

        emit SingleBridgeMsgReceived(msgId, _bridgeName, _message.nonce, msg.sender);
    }

    /// @notice Execute the message (invoke external call according to the message content) if the message
    /// @dev has reached the power threshold (the same message has been delivered by enough multiple bridges).
    /// Param values can be found in the MultiMessageMsgSent event from the source chain MultiMessageSender contract.
    function executeMessage(bytes32 msgId) external {
        ExecutionData memory _execData = msgReceived[msgId];

        if (block.timestamp > _execData.expiration) {
            revert Error.MSG_EXECUTION_PASSED_DEADLINE();
        }

        if(block.timestamp < deliveryTime[msgId] + gac.getMsgTimelock()) {
            revert Error.MSG_STILL_TIMELOCKED();
        }

        if (isExecuted[msgId]) {
            revert Error.MSG_ID_ALREADY_EXECUTED();
        }

        isExecuted[msgId] = true;

        if (messageVotes[msgId] < quorum) {
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

        if (len != _operations.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < len;) {
            _updateReceiverAdapter(_receiverAdapters[i], _operations[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Update power quorum threshold of message execution.
    function updateQuorum(uint64 _quorum) external onlySelf {
        /// NOTE: should check 2/3 ?
        if (_quorum > trustedExecutor.length || _quorum == 0) {
            revert Error.INVALID_QUORUM_THRESHOLD();
        }
        uint64 oldValue = quorum;

        quorum = _quorum;
        emit quorumUpdated(oldValue, _quorum);
    }

    /// @notice view message info, return (executed, msgPower, delivered adapters)
    function getMessageInfo(bytes32 msgId) public view returns (bool, uint256, string[] memory) {
        uint256 msgCurrentVotes = messageVotes[msgId];
        string[] memory successfulBridge = new string[](msgCurrentVotes);

        if (msgCurrentVotes != 0) {
            uint256 currIndex;
            for (uint256 i; i < trustedExecutor.length;) {
                if (isDuplicateAdapter[msgId][trustedExecutor[i]]) {
                    successfulBridge[currIndex] = IBridgeReceiverAdapter(trustedExecutor[i]).name();
                    ++currIndex;
                }

                unchecked {
                    ++i;
                }
            }
        }

        return (isExecuted[msgId], msgCurrentVotes, successfulBridge);
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _updateReceiverAdapter(address _receiverAdapter, bool _add) private {
        if (_add) {
            _addTrustedExecutor(_receiverAdapter);
        } else {
            _removeTrustedExecutor(_receiverAdapter);

            if (quorum > trustedExecutor.length) {
                revert Error.INVALID_QUORUM_THRESHOLD();
            }
        }
        emit ReceiverAdapterUpdated(_receiverAdapter, _add);
    }
}
