// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// external modules
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// interfaces
import "./interfaces/IMultiMessageReceiver.sol";
import "./interfaces/EIP5164/ExecutorAware.sol";

/// libraries
import "./MessageStruct.sol";

/// @title MultiMessageReceiver
/// @dev receives message from bridge adapters
contract MultiMessageReceiver is IMultiMessageReceiver, ExecutorAware, Initializable {
    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @notice only allows a single source chain sender
    uint256 public srcChainId;
    address public multiMessageSender;

    /// @notice minimum accumulated power precentage for each message to be executed
    uint64 public quorumThreshold;

    /// @notice bridge receiver adapters that has already delivered this message.
    /// @notice msgId => MsgInfo
    struct MsgInfo {
        bool executed;
        mapping(address => bool) from;
    }

    mapping(bytes32 => MsgInfo) public msgInfos;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    event ReceiverAdapterUpdated(address receiverAdapter, bool add);
    event MultiMessageSenderUpdated(uint256 chainId, address multiMessageSender);
    event QuorumThresholdUpdated(uint64 quorumThreshold);
    event SingleBridgeMsgReceived(
        bytes32 msgId, uint256 srcChainId, string indexed bridgeName, uint32 nonce, address receiverAdapter
    );
    event MessageExecuted(bytes32 msgId, uint256 srcChainId, uint32 nonce, address target, bytes callData);

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @notice A modifier used for restricting the caller of some functions to be configured receiver adapters.
    modifier onlyReceiverAdapter() {
        require(isTrustedExecutor(msg.sender), "not allowed bridge receiver adapter");
        _;
    }

    ///  @notice A modifier used for restricting the caller of some functions to be this contract itself.
    modifier onlySelf() {
        require(msg.sender == address(this), "not self");
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                INITIALIZER
    ////////////////////////////////////////////////////////////////*/

    /// @notice A one-time function to initialize contract states.
    function initialize(
        uint256 _srcChainId,
        address _multiMessageSender,
        address[] calldata _receiverAdapters,
        uint64 _quorumThreshold
    ) external initializer {
        require(_receiverAdapters.length > 0, "empty receiver adapter list");
        require(_quorumThreshold <= _receiverAdapters.length, "invalid threshold");
        _updateMultiMessageSender(_srcChainId, _multiMessageSender);
        for (uint256 i; i < _receiverAdapters.length; ++i) {
            require(_receiverAdapters[i] != address(0), "receiver adapter is zero address");
            _updateReceiverAdapter(_receiverAdapters[i], true);
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
    function receiveMessage(MessageStruct.Message calldata _message) external override onlyReceiverAdapter {
        uint256 _srcChainId = _fromChainId();
        require(_srcChainId == srcChainId, "not from allowed source chain");
        require(_msgSender() == multiMessageSender, "not from MultiMessageSender");
        require(_message.dstChainId == block.chainid, "dest chainId not match");

        /// This msgId is totally different with each adapters' internal msgId(which is their internal nonce essentially)
        /// Although each adapters' internal msgId is attached at the end of calldata, it's not useful to MultiMessageReceiver.
        bytes32 msgId = MessageStruct.computeMsgId(_message, uint64(_srcChainId));
        MsgInfo storage msgInfo = msgInfos[msgId];
        require(msgInfo.from[msg.sender] == false, "already received from this bridge adapter");

        msgInfo.from[msg.sender] = true;
        emit SingleBridgeMsgReceived(msgId, _srcChainId, _message.bridgeName, _message.nonce, msg.sender);
    }

    /// @notice Execute the message (invoke external call according to the message content) if the message
    /// @dev has reached the power threshold (the same message has been delivered by enough multiple bridges).
    /// Param values can be found in the MultiMessageMsgSent event from the source chain MultiMessageSender contract.
    function executeMessage(
        uint64 _srcChainId,
        uint64 _dstChainId,
        uint32 _nonce,
        address _target,
        bytes calldata _callData,
        uint64 _expiration
    ) external {
        require(_expiration < block.timestamp || _expiration == 0, "message expired");
        MessageStruct.Message memory message =
            MessageStruct.Message(_dstChainId, _nonce, _target, _callData, _expiration, "");
        bytes32 msgId = MessageStruct.computeMsgId(message, _srcChainId);
        MsgInfo storage msgInfo = msgInfos[msgId];

        require(!msgInfo.executed, "message already executed");
        msgInfo.executed = true;
        require(_computeMessagePower(msgInfo) >= quorumThreshold, "threshold not met");

        (bool ok,) = _target.call(_callData);
        require(ok, "external message execution failed");
        emit MessageExecuted(msgId, _srcChainId, _nonce, _target, _callData);
    }

    /// @notice Update bridge receiver adapters.
    /// @dev This function can only be called by executeMessage() invoked within receiveMessage() of this contract,
    /// which means the only party who can make these updates is the caller of the MultiMessageSender at the source chain.
    function updateReceiverAdapter(address[] calldata _receiverAdapters, bool[] calldata _operations)
        external
        onlySelf
    {
        require(_receiverAdapters.length == _operations.length, "mismatch length");
        for (uint256 i; i < _receiverAdapters.length; ++i) {
            _updateReceiverAdapter(_receiverAdapters[i], _operations[i]);
        }
    }

    /// @notice Update MultiMessageSender on source chain.
    /// @dev This function can only be called by executeMessage() invoked within receiveMessage() of this contract,
    /// which means the only party who can make these updates is the caller of the MultiMessageSender at the source chain.
    function updateMultiMessageSender(uint256 _srcChainId, address _multiMessageSender) external onlySelf {
        _updateMultiMessageSender(_srcChainId, _multiMessageSender);
    }

    /// @notice Update power quorum threshold of message execution.
    /// @dev This function can only be called by executeMessage() invoked within receiveMessage() of this contract,
    /// which means the only party who can make these updates is the caller of the MultiMessageSender at the source chain.
    function updateQuorumThreshold(uint64 _quorumThreshold) external onlySelf {
        require(_quorumThreshold <= trustedExecutor.length && _quorumThreshold > 0, "invalid threshold");
        quorumThreshold = _quorumThreshold;
        emit QuorumThresholdUpdated(_quorumThreshold);
    }

    /// @notice View message info, return (executed, msgPower, delivered adapters)
    function getMessageInfo(bytes32 msgId) public view returns (bool, uint64, address[] memory) {
        MsgInfo storage msgInfo = msgInfos[msgId];
        uint64 msgPower = _computeMessagePower(msgInfo);
        address[] memory adapters = new address[](msgPower);
        if (msgPower > 0) {
            uint32 n = 0;
            for (uint64 i = 0; i < trustedExecutor.length; i++) {
                address adapter = trustedExecutor[i];
                if (msgInfo.from[adapter]) {
                    adapters[n++] = adapter;
                }
            }
        }
        return (msgInfo.executed, msgPower, adapters);
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _computeMessagePower(MsgInfo storage _msgInfo) private view returns (uint64) {
        uint64 msgPower;
        for (uint256 i; i < trustedExecutor.length; ++i) {
            address adapter = trustedExecutor[i];
            if (_msgInfo.from[adapter]) {
                ++msgPower;
            }
        }
        return msgPower;
    }

    function _updateReceiverAdapter(address _receiverAdapter, bool _add) private {
        if (_add) {
            _addTrustedExecutor(_receiverAdapter);
        } else {
            _removeTrustedExecutor(_receiverAdapter);
            require(quorumThreshold <= trustedExecutor.length, "insufficient total power after removal");
        }
        emit ReceiverAdapterUpdated(_receiverAdapter, _add);
    }

    function _updateMultiMessageSender(uint256 _srcChainId, address _multiMessageSender) private {
        require(_srcChainId != 0, "srcChainId is zero");
        require(_multiMessageSender != address(0), "multiMessageSender is zero address");
        srcChainId = _srcChainId;
        multiMessageSender = _multiMessageSender;
        emit MultiMessageSenderUpdated(_srcChainId, _multiMessageSender);
    }
}
