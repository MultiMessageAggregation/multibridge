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
    using MessageLibrary for MessageLibrary.Message;

    /*/////////////////////////////////////////////////////////////////
                                    STRUCTS
    ////////////////////////////////////////////////////////////////*/
    struct RemoteCallArgs {
        uint256 dstChainId;
        address target;
        bytes callData;
        uint256 nativeValue;
        uint256 expiration;
        address refundAddress;
        uint256[] fees;
        uint256 successThreshold;
        address[] excludedAdapters;
    }

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
    /// The list is always kept in ascending order by adapter address
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

    /// @notice is emitted when owner updates the one or more sender adapters
    /// @param senderAdapters the address of the sender adapters that were updated
    /// @param add true if the sender adapters were added, false if they were removed
    event SenderAdaptersUpdated(address[] indexed senderAdapters, bool add);

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Restricts the caller to the owner configured in GAC.
    modifier onlyGlobalOwner() {
        if (msg.sender != senderGAC.getGlobalOwner()) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    /// @dev checks if msg.sender is the authorised caller configured in GAC
    modifier onlyCaller() {
        if (msg.sender != senderGAC.authorisedCaller()) {
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

    /// @param _dstChainId is the destination chainId
    /// @param _target is the target execution point on the destination chain
    /// @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData))
    /// @param _nativeValue is the value to be sent to _target by low-level call (eg. address(_target).call{value: _nativeValue}(_callData))
    /// @param _expiration refers to the number of seconds that a message remains valid before it is considered stale and can no longer be executed.
    /// @param _refundAddress refers to the refund address for any extra native tokens paid
    /// @param _fees refers to the fees to pay to each sender adapter that is not in the exclusion list specified by _excludedAdapters.
    ///         The fees are in the same order as the sender adapters in the senderAdapters list, after the exclusion list is applied.
    /// @param _successThreshold specifies the minimum number of bridges that must successfully dispatch the message for this call to succeed.
    /// @param _excludedAdapters are the sender adapters to be excluded from relaying the message, in ascending order by address
    function remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address _refundAddress,
        uint256[] calldata _fees,
        uint256 _successThreshold,
        address[] memory _excludedAdapters
    ) external payable onlyCaller validateExpiration(_expiration) {
        _remoteCall(
            RemoteCallArgs(
                _dstChainId,
                _target,
                _callData,
                _nativeValue,
                _expiration,
                _refundAddress,
                _fees,
                _successThreshold,
                _excludedAdapters
            )
        );
    }

    /// @notice Add bridge sender adapters
    /// @param _additions are the adapter address to add, in ascending order with no duplicates
    function addSenderAdapters(address[] calldata _additions) external onlyGlobalOwner {
        _checkAdaptersOrder(_additions);

        address[] memory existings = senderAdapters;

        if (existings.length == 0) {
            senderAdapters = _additions;
            _logSenderAdapterUpdates(_additions, true);
            return;
        }

        uint256 i;
        uint256 j;
        uint256 k;
        address[] memory merged = new address[](existings.length + _additions.length);
        while (i < existings.length && j < _additions.length) {
            address existing = existings[i];
            address added = _additions[j];
            if (existing < added) {
                merged[k] = existing;
                unchecked {
                    ++i;
                }
            } else if (existing == added) {
                revert Error.DUPLICATE_SENDER_ADAPTER();
            } else {
                merged[k] = added;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++k;
            }
        }
        while (i < existings.length) {
            merged[k] = existings[i];
            unchecked {
                ++i;
                ++k;
            }
        }
        while (j < _additions.length) {
            merged[k] = _additions[j];
            unchecked {
                ++j;
                ++k;
            }
        }

        senderAdapters = merged;
        _logSenderAdapterUpdates(_additions, true);
    }

    /// @notice Remove bridge sender adapters
    /// @param _removals are the adapter addresses to remove
    function removeSenderAdapters(address[] calldata _removals) external onlyGlobalOwner {
        _checkAdaptersOrder(_removals);

        address[] memory existings = senderAdapters;
        address[] memory filtered = _filterAdapters(existings, _removals);

        senderAdapters = filtered;
        _logSenderAdapterUpdates(_removals, false);
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _remoteCall(RemoteCallArgs memory _args) private {
        (address mmaReceiver, address[] memory adapters) = _checkAndProcessArgs(
            _args.dstChainId,
            _args.target,
            _args.refundAddress,
            _args.successThreshold,
            _args.fees,
            _args.excludedAdapters
        );

        /// @dev increments nonce
        ++nonce;

        MessageLibrary.Message memory message = MessageLibrary.Message(
            block.chainid,
            _args.dstChainId,
            _args.target,
            nonce,
            _args.callData,
            _args.nativeValue,
            block.timestamp + _args.expiration
        );
        bytes32 msgId = message.computeMsgId();
        (bool[] memory adapterSuccess, uint256 successCount) =
            _dispatchMessages(adapters, mmaReceiver, _args.dstChainId, message, _args.fees);

        if (successCount < _args.successThreshold) {
            revert Error.MULTI_MESSAGE_SEND_FAILED();
        }

        emit MultiBridgeMessageSent(
            msgId,
            nonce,
            _args.dstChainId,
            _args.target,
            _args.callData,
            _args.nativeValue,
            _args.expiration,
            adapters,
            adapterSuccess
        );

        /// refund remaining fee
        if (address(this).balance > 0) {
            _safeTransferETH(_args.refundAddress, address(this).balance);
        }
    }

    function _checkAndProcessArgs(
        uint256 _dstChainId,
        address _target,
        address _refundAddress,
        uint256 _successThreshold,
        uint256[] memory _fees,
        address[] memory _excludedAdapters
    ) private view returns (address mmaReceiver, address[] memory adapters) {
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

        mmaReceiver = senderGAC.remoteMultiBridgeMessageReceiver(_dstChainId);

        if (mmaReceiver == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        adapters = _filterAdapters(senderAdapters, _excludedAdapters);

        if (adapters.length == 0) {
            revert Error.NO_SENDER_ADAPTER_FOUND();
        }

        if (_successThreshold > adapters.length) {
            revert Error.MULTI_MESSAGE_SEND_FAILED();
        }

        if (adapters.length != _fees.length) {
            revert Error.INVALID_SENDER_ADAPTER_FEES();
        }
        uint256 totalFees;
        for (uint256 i; i < _fees.length;) {
            totalFees += _fees[i];
            unchecked {
                ++i;
            }
        }
        if (totalFees > msg.value) {
            revert Error.INVALID_MSG_VALUE();
        }
    }

    function _dispatchMessages(
        address[] memory _adapters,
        address _mmaReceiver,
        uint256 _dstChainId,
        MessageLibrary.Message memory _message,
        uint256[] memory _fees
    ) private returns (bool[] memory, uint256) {
        uint256 len = _adapters.length;
        bool[] memory successes = new bool[](len);
        uint256 successCount;

        for (uint256 i; i < len;) {
            /// @dev if one bridge is paused, the flow shouldn't be broken
            try IMessageSenderAdapter(_adapters[i]).dispatchMessage{value: _fees[i]}(
                _dstChainId, _mmaReceiver, abi.encode(_message)
            ) {
                successes[i] = true;
                ++successCount;
            } catch {
                successes[i] = false;
                emit MessageSendFailed(_adapters[i], _message);
            }

            unchecked {
                ++i;
            }
        }
        return (successes, successCount);
    }

    function _filterAdapters(address[] memory _existings, address[] memory _removals)
        private
        pure
        returns (address[] memory)
    {
        if (_existings.length < _removals.length) {
            revert Error.SENDER_ADAPTER_NOT_EXIST();
        }

        uint256 i;
        uint256 j;
        uint256 k;
        address[] memory filtered = new address[](_existings.length - _removals.length);
        while (i < _existings.length && j < _removals.length) {
            address existing = _existings[i];
            address removed = _removals[j];
            if (existing == removed) {
                unchecked {
                    ++j;
                }
            } else {
                if (k == filtered.length) {
                    revert Error.SENDER_ADAPTER_NOT_EXIST();
                }
                filtered[k] = existing;
                unchecked {
                    ++k;
                }
                if (existing > removed) {
                    unchecked {
                        ++j;
                    }
                }
            }
            unchecked {
                ++i;
            }
        }
        while (i < _existings.length) {
            if (k == filtered.length) {
                revert Error.SENDER_ADAPTER_NOT_EXIST();
            }
            filtered[k] = _existings[i];
            unchecked {
                ++i;
                ++k;
            }
        }
        return filtered;
    }

    /// @dev validates if the adapters addresses are in ascending order
    /// @param _adapters are the addresses to check
    function _checkAdaptersOrder(address[] memory _adapters) private pure {
        uint256 len = _adapters.length;

        address prev;
        for (uint256 i; i < len;) {
            address curr = _adapters[i];
            if (curr < prev) {
                revert Error.INVALID_SENDER_ADAPTER_ORDER();
            } else if (curr == prev) {
                if (curr == address(0)) {
                    revert Error.ZERO_ADDRESS_INPUT();
                }
                revert Error.DUPLICATE_SENDER_ADAPTER();
            }
            prev = curr;
            unchecked {
                ++i;
            }
        }
    }

    function _logSenderAdapterUpdates(address[] memory _updates, bool _add) private {
        emit SenderAdaptersUpdated(_updates, _add);
    }

    /// @dev transfer ETH to an address, revert if it fails.
    /// @param to recipient of the transfer
    /// @param value the amount to send
    function _safeTransferETH(address to, uint256 value) private {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "safeTransferETH: ETH transfer failed");
    }
}
