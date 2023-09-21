// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// interfaces
import "./interfaces/adapters/IMessageSenderAdapter.sol";
import "./interfaces/IMultiBridgeMessageReceiver.sol";
import "./controllers/MessageSenderGAC.sol";

/// libraries
import "./libraries/Message.sol";
import "./libraries/Error.sol";

/// @title Multi-bridge Message Sender
/// @notice Sends cross-chain messages through multiple bridge sender adapters.
/// The contract has only a single authorised caller that can send messages, and an owner that can change key parameters.
/// Both of these are configured in the Global Access Control contract. In the case of Uniswap, both the authorised caller
/// and owner should be set to the Uniswap V2 Timelock contract on Ethereum.
contract MultiBridgeMessageSender {
    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Global Access Controller (GAC) contract
    MessageSenderGAC public immutable senderGAC;

    /// @dev the minimum and maximum duration that a message's expiration parameter can be set to
    uint256 public constant MIN_MESSAGE_EXPIRATION = 2 days;
    uint256 public constant MAX_MESSAGE_EXPIRATION = 30 days;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev the list of message sender adapters for different bridges, each of which implements the IMessageSenderAdapter interface.
    address[] public senderAdapters;

    /// @dev nonce for msgId uniqueness
    uint256 public nonce;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    /// @notice is emitted after a cross-chain message is sent through multiple bridge sender adapters
    /// This event is emitted even if the message fails to be sent through one or more of the adapters,
    /// so the success status for each bridge adapter should be checked.
    /// @param msgId is the unique identifier of the message
    /// @param nonce is the nonce of the message
    /// @param dstChainId is the destination chain id of the message
    /// @param target is the target execution address on the destination chain
    /// @param callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData))
    /// @param nativeValue is the value to be sent to _target by low-level call (eg. address(_target).call{value: _nativeValue}(_callData))
    /// @param expiration refers to the number seconds that a message remains valid before it is considered stale and can no longer be executed.
    /// @param senderAdapters are the sender adapters that were used to send the message
    /// @param adapterSuccess are the message sending success status for each of the corresponding adapters listed in senderAdapters
    event MultiBridgeMessageSent(
        bytes32 indexed msgId,
        uint256 nonce,
        uint256 indexed dstChainId,
        address indexed target,
        bytes callData,
        uint256 nativeValue,
        uint256 expiration,
        address[] senderAdapters,
        bool[] adapterSuccess
    );

    /// @notice is emitted if sending a cross-chain message through a bridge sender adapter fails
    /// @param senderAdapter is the address of the sender adapter that failed to send the message
    /// @param message is the message that failed to be sent
    event MessageSendFailed(address indexed senderAdapter, MessageLibrary.Message message);

    /// @notice is emitted when owner updates the sender adapter
    /// @param senderAdapter the address of the sender adapter that was updated
    /// @param add true if the sender adapter was added, false if it was removed
    event SenderAdapterUpdated(address indexed senderAdapter, bool add);

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @dev checks if msg.sender is the owner configured in GAC
    modifier onlyOwner() {
        if (msg.sender != senderGAC.getGlobalOwner()) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    /// @dev checks if msg.sender is the authorised caller configured in GAC
    modifier onlyCaller() {
        if (msg.sender != senderGAC.getAuthorisedCaller()) {
            revert Error.INVALID_PRIVILEGED_CALLER();
        }
        _;
    }

    /// @dev validates the expiration provided by the user
    modifier validateExpiration(uint256 _expiration) {
        if (_expiration < MIN_MESSAGE_EXPIRATION || _expiration > MAX_MESSAGE_EXPIRATION) {
            revert Error.INVALID_EXPIRATION_DURATION();
        }

        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _senderGAC is the controller/registry of MMA
    constructor(address _senderGAC) {
        if (_senderGAC == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        senderGAC = MessageSenderGAC(_senderGAC);
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Call a remote function on a destination chain by sending multiple copies of a cross-chain message
    /// via all available bridges. This function can only be called by the authorised called configured in the GAC.
    /// @dev a fee in native token may be required by each message bridge to send messages. Any native token fee remained
    /// will be refunded back to a refund address defined in the _refundAddress parameter.
    /// Caller can use estimateTotalMessageFee() to get total message fees before calling this function.
    /// @param _dstChainId is the destination chainId
    /// @param _target is the target execution point on the destination chain
    /// @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData))
    /// @param _nativeValue is the value to be sent to _target by low-level call (eg. address(_target).call{value: _nativeValue}(_callData))
    /// @param _expiration refers to the number of seconds that a message remains valid before it is considered stale and can no longer be executed.
    /// @param _refundAddress refers to the refund address for any extra native tokens paid
    function remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address _refundAddress
    ) external payable onlyCaller validateExpiration(_expiration) {
        address[] memory excludedAdapters;
        _remoteCall(_dstChainId, _target, _callData, _nativeValue, _expiration, _refundAddress, excludedAdapters);
    }

    /// @param _dstChainId is the destination chainId
    /// @param _target is the target execution point on the destination chain
    /// @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData))
    /// @param _nativeValue is the value to be sent to _target by low-level call (eg. address(_target).call{value: _nativeValue}(_callData))
    /// @param _expiration refers to the number of seconds that a message remains valid before it is considered stale and can no longer be executed.
    /// @param _excludedAdapters are the sender adapters to be excluded from relaying the message
    /// @param _refundAddress refers to the refund address for any extra native tokens paid
    function remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address _refundAddress,
        address[] calldata _excludedAdapters
    ) external payable onlyCaller validateExpiration(_expiration) {
        _remoteCall(_dstChainId, _target, _callData, _nativeValue, _expiration, _refundAddress, _excludedAdapters);
    }

    /// @notice Add bridge sender adapters
    /// @param _adapters is the adapter address to add
    function addSenderAdapters(address[] calldata _adapters) external onlyOwner {
        for (uint256 i; i < _adapters.length;) {
            _addSenderAdapter(_adapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Remove bridge sender adapters
    /// @param _adapters is the adapter address to remove
    function removeSenderAdapters(address[] calldata _adapters) external onlyOwner {
        for (uint256 i; i < _adapters.length;) {
            _removeSenderAdapter(_adapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice A helper function for estimating total required message fee by all available message bridges.
    function estimateTotalMessageFee(
        uint256 _dstChainId,
        address _multiBridgeMessageReceiver,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue
    ) public view returns (uint256 totalFee) {
        MessageLibrary.Message memory message =
            MessageLibrary.Message(block.chainid, _dstChainId, _target, nonce, _callData, _nativeValue, 0);
        bytes memory data;

        /// @dev writes to memory for saving gas
        address[] storage adapters = senderAdapters;

        /// @dev generates the dst chain function call
        data = abi.encodeWithSelector(IMultiBridgeMessageReceiver.receiveMessage.selector, message);

        for (uint256 i; i < adapters.length; ++i) {
            uint256 fee = IMessageSenderAdapter(adapters[i]).getMessageFee(
                uint256(_dstChainId), _multiBridgeMessageReceiver, data
            );

            totalFee += fee;
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address _refundAddress,
        address[] memory _excludedAdapters
    ) private {
        if (_dstChainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        if (_dstChainId == block.chainid) {
            revert Error.INVALID_DST_CHAIN();
        }

        if (_target == address(0)) {
            revert Error.INVALID_TARGET();
        }

        if (_refundAddress == address(0) || _refundAddress == address(this)) {
            revert Error.INVALID_REFUND_ADDRESS();
        }

        address mmaReceiver = senderGAC.getRemoteMultiBridgeMessageReceiver(_dstChainId);

        if (mmaReceiver == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        /// @dev increments nonce
        ++nonce;
        MessageLibrary.Message memory message = MessageLibrary.Message(
            block.chainid, _dstChainId, _target, nonce, _callData, _nativeValue, block.timestamp + _expiration
        );
        bytes32 msgId = MessageLibrary.computeMsgId(message);

        address[] memory adapters = _getSenderAdapters(_excludedAdapters);

        if (adapters.length == 0) {
            revert Error.NO_SENDER_ADAPTER_FOUND();
        }

        bool[] memory adapterSuccesses = _dispatchMessages(adapters, mmaReceiver, _dstChainId, message);
        emit MultiBridgeMessageSent(
            msgId, nonce, _dstChainId, _target, _callData, _nativeValue, _expiration, adapters, adapterSuccesses
        );

        /// refund remaining fee
        if (address(this).balance > 0) {
            _safeTransferETH(_refundAddress, address(this).balance);
        }
    }

    function _addSenderAdapter(address _adapter) private {
        if (_adapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        /// @dev reverts if it finds a duplicate
        _checkDuplicates(_adapter);

        senderAdapters.push(_adapter);
        emit SenderAdapterUpdated(_adapter, true);
    }

    function _removeSenderAdapter(address _adapter) private {
        uint256 lastIndex = senderAdapters.length - 1;

        for (uint256 i; i < senderAdapters.length; ++i) {
            if (senderAdapters[i] == _adapter) {
                if (i < lastIndex) {
                    senderAdapters[i] = senderAdapters[lastIndex];
                }

                senderAdapters.pop();

                emit SenderAdapterUpdated(_adapter, false);
                return;
            }
        }
    }

    function _dispatchMessages(
        address[] memory _adapters,
        address _mmaReceiver,
        uint256 _dstChainId,
        MessageLibrary.Message memory _message
    ) private returns (bool[] memory) {
        uint256 len = _adapters.length;
        bool[] memory successes = new bool[](len);
        for (uint256 i; i < len;) {
            IMessageSenderAdapter bridgeAdapter = IMessageSenderAdapter(_adapters[i]);
            /// @dev assumes CREATE2 deployment for mma sender & receiver
            uint256 fee = bridgeAdapter.getMessageFee(_dstChainId, _mmaReceiver, abi.encode(_message));

            /// @dev if one bridge is paused, the flow shouldn't be broken
            try IMessageSenderAdapter(_adapters[i]).dispatchMessage{value: fee}(
                _dstChainId, _mmaReceiver, abi.encode(_message)
            ) {
                successes[i] = true;
            } catch {
                successes[i] = false;
                emit MessageSendFailed(_adapters[i], _message);
            }

            unchecked {
                ++i;
            }
        }
        return successes;
    }

    function _getSenderAdapters(address[] memory _exclusions) private view returns (address[] memory) {
        uint256 allLen = senderAdapters.length;
        uint256 exclLen = _exclusions.length;

        address[] memory inclAdapters = new address[](allLen - exclLen);
        uint256 inclCount;
        for (uint256 i; i < allLen;) {
            bool excluded = false;
            for (uint256 j; j < exclLen;) {
                if (senderAdapters[i] == _exclusions[j]) {
                    excluded = true;
                    break;
                }
                unchecked {
                    ++j;
                }
            }
            if (!excluded) {
                inclAdapters[inclCount++] = senderAdapters[i];
            }
            unchecked {
                ++i;
            }
        }
        return inclAdapters;
    }

    /// @dev validates if the sender adapter already exists
    /// @param _adapter is the address of the sender to check
    function _checkDuplicates(address _adapter) internal view {
        uint256 len = senderAdapters.length;

        for (uint256 i; i < len;) {
            if (senderAdapters[i] == _adapter) {
                revert Error.DUPLICATE_SENDER_ADAPTER();
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev transfer ETH to an address, revert if it fails.
    /// @param to recipient of the transfer
    /// @param value the amount to send
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "safeTransferETH: ETH transfer failed");
    }
}
