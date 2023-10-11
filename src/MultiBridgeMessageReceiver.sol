// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// interfaces
import "./interfaces/controllers/IGAC.sol";
import "./interfaces/adapters/IMessageReceiverAdapter.sol";
import "./interfaces/IMultiBridgeMessageReceiver.sol";
import "./libraries/EIP5164/ExecutorAware.sol";
import "./interfaces/controllers/IGovernanceTimelock.sol";

/// libraries
import "./libraries/Error.sol";
import "./libraries/Message.sol";

/// @title Multi-bridge message receiver.
/// @notice This contract is deployed on each destination chain, and receives messages sent by the MultiBridgeMessageSender
/// contract on the source chain, through multiple bridge adapters. A message is considered valid and can be executed
/// if it has been delivered by enough trusted bridge receiver adapters (i.e. has achieved a configured quorum threshold),
/// before the message's expiration. If a message is successfully validated in time, it is queued for execution on the
/// governance timelock contract.
/// @dev The contract only accepts messages from trusted bridge receiver adapters, each of which implements the
/// IMessageReceiverAdapter interface.
contract MultiBridgeMessageReceiver is IMultiBridgeMessageReceiver, ExecutorAware {
    using MessageLibrary for MessageLibrary.Message;
    using MessageLibrary for MessageLibrary.MessageExecutionParams;

    /// @notice the id of the source chain that this contract can receive messages from
    uint256 public immutable srcChainId;
    /// @notice the global access control contract
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @notice minimum number of bridges that must deliver a message for it to be considered valid
    uint64 public quorum;

    /// @notice the address of governance timelock contract on the same chain, that a message will be forwarded to for execution
    address public governanceTimelock;

    /// @notice maintains which bridge adapters have delivered each message
    mapping(bytes32 msgId => mapping(address receiverAdapter => bool delivered)) public msgDeliveries;

    /// @notice count of bridge adapters that have delivered each message
    mapping(bytes32 msgId => uint256 deliveryCount) public msgDeliveryCount;

    /// @notice the hash of the params required for executing a message
    mapping(bytes32 msgId => bytes32 execParamsHash) public msgExecParamsHash;

    /// @notice whether a message has been sent to the governance timelock for execution
    mapping(bytes32 msgId => bool scheduled) public isExecutionScheduled;

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the caller is a trusted bridge receiver adapter
    modifier onlyReceiverAdapter() {
        if (!isTrustedExecutor(msg.sender)) {
            revert Error.INVALID_RECEIVER_ADAPTER();
        }
        _;
    }

    /// @notice Restricts the caller to the owner configured in GAC.
    modifier onlyGlobalOwner() {
        if (!gac.isGlobalOwner(msg.sender)) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @notice sets the initial parameters
    constructor(uint256 _srcChainId, address _gac, address[] memory _receiverAdapters, uint64 _quorum) {
        if (_srcChainId == 0) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }
        if (_gac == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        srcChainId = _srcChainId;
        gac = IGAC(_gac);

        for (uint256 i; i < _receiverAdapters.length;) {
            _updateReceiverAdapter(_receiverAdapters[i], true);
            unchecked {
                ++i;
            }
        }
        _updateQuorum(_quorum);
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice receive messages from allowed bridge receiver adapters
    /// @param _message is the crosschain message sent by the mma sender
    function receiveMessage(MessageLibrary.Message calldata _message) external override onlyReceiverAdapter {
        if (_message.dstChainId != block.chainid) {
            revert Error.INVALID_DST_CHAIN();
        }

        if (_message.target == address(0)) {
            revert Error.INVALID_TARGET();
        }

        if (_message.srcChainId != srcChainId) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// this msgId is totally different with each adapters' internal msgId(which is their internal nonce essentially)
        /// although each adapters' internal msgId is attached at the end of calldata, it's not useful to MultiBridgeMessageReceiver.sol.
        bytes32 msgId = _message.computeMsgId();

        if (msgDeliveries[msgId][msg.sender]) {
            revert Error.DUPLICATE_MESSAGE_DELIVERY_BY_ADAPTER();
        }

        /// @dev checks if msgId was already sent to the timelock for eventual execution
        if (isExecutionScheduled[msgId]) {
            revert Error.MSG_ID_ALREADY_SCHEDULED();
        }

        msgDeliveries[msgId][msg.sender] = true;

        /// increment vote count for a message
        ++msgDeliveryCount[msgId];

        /// stores the hash of the execution params required
        bytes32 prevStoredHash = msgExecParamsHash[msgId];

        /// stores the message if the amb is the first one delivering the message
        if (prevStoredHash == bytes32(0)) {
            msgExecParamsHash[msgId] = _message.computeExecutionParamsHash();
        }

        string memory bridgeName = IMessageReceiverAdapter(msg.sender).name();
        emit BridgeMessageReceived(msgId, bridgeName, _message.nonce, msg.sender);
    }

    /// @inheritdoc IMultiBridgeMessageReceiver
    function scheduleMessageExecution(bytes32 _msgId, MessageLibrary.MessageExecutionParams calldata _execParams)
        external
        override
    {
        bytes32 execParamsHash = msgExecParamsHash[_msgId];
        if (_execParams.computeExecutionParamsHash() != execParamsHash) {
            revert Error.EXEC_PARAMS_HASH_MISMATCH();
        }

        /// @dev validates if msg execution is not beyond expiration
        if (block.timestamp > _execParams.expiration) {
            revert Error.MSG_EXECUTION_PASSED_DEADLINE();
        }

        /// @dev checks if msgId was already sent to the timelock for eventual execution
        if (isExecutionScheduled[_msgId]) {
            revert Error.MSG_ID_ALREADY_SCHEDULED();
        }

        isExecutionScheduled[_msgId] = true;

        /// @dev validates message quorum
        if (msgDeliveryCount[_msgId] < quorum) {
            revert Error.QUORUM_NOT_ACHIEVED();
        }

        /// @dev queues the action on timelock for execution
        IGovernanceTimelock(governanceTimelock).scheduleTransaction(
            _execParams.target, _execParams.value, _execParams.callData
        );

        emit MessageExecutionScheduled(
            _msgId, _execParams.target, _execParams.value, _execParams.nonce, _execParams.callData
        );
    }

    /// @notice update the governance timelock contract.
    /// @dev called by admin to update the timelock contract
    function updateGovernanceTimelock(address _governanceTimelock) external onlyGlobalOwner {
        if (_governanceTimelock == address(0)) {
            revert Error.ZERO_GOVERNANCE_TIMELOCK();
        }
        address oldGovernanceTimelock = governanceTimelock;
        governanceTimelock = _governanceTimelock;
        emit GovernanceTimelockUpdated(oldGovernanceTimelock, _governanceTimelock);
    }

    /// @notice Update bridge receiver adapters.
    /// @dev called by admin to update receiver bridge adapters on all other chains
    function updateReceiverAdapters(address[] calldata _receiverAdapters, bool[] calldata _operations)
        external
        override
        onlyGlobalOwner
    {
        _updateReceiverAdapters(_receiverAdapters, _operations);
        _validateQuorum(quorum);
    }

    /// @notice Update bridge receiver adapters and quorum
    /// @dev called by admin to update receiver bridge adapters on all other chains along with quorum
    function updateReceiverAdaptersAndQuorum(
        address[] calldata _receiverAdapters,
        bool[] calldata _operations,
        uint64 _newQuorum
    ) external override onlyGlobalOwner {
        _updateReceiverAdapters(_receiverAdapters, _operations);
        _updateQuorum(_newQuorum);
    }

    /// @notice Update power quorum threshold of message execution.
    function updateQuorum(uint64 _quorum) external override onlyGlobalOwner {
        _updateQuorum(_quorum);
    }

    /*/////////////////////////////////////////////////////////////////
                            VIEW/READ-ONLY FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice View message info
    /// @return isExecutionScheduled is true if the message has been sent to the timelock for execution
    /// @return msgCurrentVotes is the number of bridges that have delivered the message
    /// @return successfulBridge is the list of bridges that have delivered the message
    function getMessageInfo(bytes32 _msgId) public view returns (bool, uint256, string[] memory) {
        uint256 msgCurrentVotes = msgDeliveryCount[_msgId];
        string[] memory successfulBridge = new string[](msgCurrentVotes);

        if (msgCurrentVotes != 0) {
            uint256 currIndex;
            address[] memory executors = getTrustedExecutors();
            for (uint256 i; i < executors.length;) {
                if (msgDeliveries[_msgId][executors[i]]) {
                    successfulBridge[currIndex] = IMessageReceiverAdapter(executors[i]).name();
                    ++currIndex;
                }

                unchecked {
                    ++i;
                }
            }
        }

        return (isExecutionScheduled[_msgId], msgCurrentVotes, successfulBridge);
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _updateQuorum(uint64 _quorum) private {
        _validateQuorum(_quorum);

        uint64 oldValue = quorum;

        quorum = _quorum;
        emit QuorumUpdated(oldValue, _quorum);
    }

    function _updateReceiverAdapters(address[] memory _receiverAdapters, bool[] memory _operations) private {
        uint256 len = _receiverAdapters.length;

        if (len == 0) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

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

    function _updateReceiverAdapter(address _receiverAdapter, bool _add) private {
        if (_receiverAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }
        bool success = _add ? _addTrustedExecutor(_receiverAdapter) : _removeTrustedExecutor(_receiverAdapter);

        if (!success) {
            // only fails because we are either attempting to add an existing adapter, or remove a non-existing adapter
            revert Error.UPDATE_RECEIVER_ADAPTER_FAILED(_add ? "adapter already added" : "adapter not found");
        }

        emit BridgeReceiverAdapterUpdated(_receiverAdapter, _add);
    }

    function _validateQuorum(uint256 _quorum) private view {
        if (_quorum > trustedExecutorsCount() || _quorum == 0) {
            revert Error.INVALID_QUORUM_THRESHOLD();
        }
    }
}
