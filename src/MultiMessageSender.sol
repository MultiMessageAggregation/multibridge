// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// interfaces
import "./interfaces/IBridgeSenderAdapter.sol";
import "./interfaces/IMultiMessageReceiver.sol";
import "./interfaces/IGAC.sol";

/// libraries
import "./libraries/Message.sol";
import "./libraries/Error.sol";

/// @title MultiMessageSender
/// @dev handles the routing of message from external sender to bridge adapters
contract MultiMessageSender {
    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    IGAC public immutable gac;

    uint256 public constant MINIMUM_EXPIRATION = 2 days;
    uint256 public constant MAXIMUM_EXPIRATION = 30 days;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev bridge sender adapters available
    address[] public senderAdapters;

    /// @dev nonce for msgId uniqueness
    uint256 public nonce;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    /// @dev is emitted when a cross-chain message is sent
    event MultiMessageMsgSent(
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

    /// @dev is emitted when owner updates the sender adapter
    /// @notice add being false indicates removal of the adapter
    event SenderAdapterUpdated(address senderAdapter, bool add);

    /// @dev is emitted if cross-chain message fails
    event ErrorSendMessage(address senderAdapter, MessageLibrary.Message message);

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @dev checks if msg.sender is only the owner (global controller)
    modifier onlyOwner() {
        if (msg.sender != gac.getGlobalOwner()) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    /// @dev checks if msg.sender is caller configured in the constructor
    modifier onlyCaller() {
        if (msg.sender != gac.getMultiMessageCaller()) {
            revert Error.INVALID_PRIVILEGED_CALLER();
        }
        _;
    }

    /// @dev validates the expiration provided by the user
    modifier validateExpiration(uint256 _expiration) {
        if (_expiration < MINIMUM_EXPIRATION) {
            revert Error.INVALID_EXPIRATION_MIN();
        }

        if (_expiration > MAXIMUM_EXPIRATION) {
            revert Error.INVALID_EXPIRATION_MAX();
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
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Call a remote function on a destination chain by sending multiple copies of a cross-chain message
    /// via all available bridges.

    /// @dev a fee in native token may be required by each message bridge to send messages. Any native token fee remained
    /// will be refunded back to msg.sender, which requires caller being able to receive native token.
    /// Caller can use estimateTotalMessageFee() to get total message fees before calling this function.

    /// @param _dstChainId is the destination chainId
    /// @param _target is the target execution point on dst chain
    /// @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData))
    /// @param _nativeValue is the value to be sent to _target by low-level call (eg. address(_target).call{value: _nativeValue}(_callData))
    /// @param _expiration refers to the number of days that a message remains valid before it is considered stale and can no longer be executed.
    function remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration
    ) external payable onlyCaller {
        address[] memory excludedAdapters;
        _remoteCall(_dstChainId, _target, _callData, _nativeValue, _expiration, excludedAdapters);
    }

    /// @param _dstChainId is the destination chainId
    /// @param _target is the target execution point on dst chain
    /// @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData))
    /// @param _nativeValue is the value to be sent to _target by low-level call (eg. address(_target).call{value: _nativeValue}(_callData))
    /// @param _excludedAdapters are the sender adapters to be excluded from relaying the message
    /// @param _expiration refers to the number of days that a message remains valid before it is considered stale and can no longer be executed.
    function remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address[] calldata _excludedAdapters
    ) external payable onlyCaller {
        _remoteCall(_dstChainId, _target, _callData, _nativeValue, _expiration, _excludedAdapters);
    }

    /// @notice Add bridge sender adapters
    /// @param _senderAdapters is the adapter address to add
    function addSenderAdapters(address[] calldata _senderAdapters) external onlyOwner {
        for (uint256 i; i < _senderAdapters.length;) {
            _addSenderAdapter(_senderAdapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Remove bridge sender adapters
    /// @param _senderAdapters is the adapter address to remove
    function removeSenderAdapters(address[] calldata _senderAdapters) external onlyOwner {
        for (uint256 i; i < _senderAdapters.length;) {
            _removeSenderAdapter(_senderAdapters[i]);

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
        address _multiMessageReceiver,
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
        data = abi.encodeWithSelector(IMultiMessageReceiver.receiveMessage.selector, message);

        for (uint256 i; i < adapters.length; ++i) {
            uint256 fee =
                IBridgeSenderAdapter(adapters[i]).getMessageFee(uint256(_dstChainId), _multiMessageReceiver, data);

            totalFee += fee;
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    struct LocalCallVars {
        address[] adapters;
        uint256 adapterLength;
        bool[] adapterSuccess;
        bytes32 msgId;
    }

    function _remoteCall(
        uint256 _dstChainId,
        address _target,
        bytes calldata _callData,
        uint256 _nativeValue,
        uint256 _expiration,
        address[] memory _excludedAdapters
    ) private {
        LocalCallVars memory v;

        if (_dstChainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        if (_target == address(0)) {
            revert Error.INVALID_TARGET();
        }

        address mmaReceiver = gac.getMultiMessageReceiver(_dstChainId);

        if (mmaReceiver == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        /// @dev writes to memory for gas saving
        v.adapters = new address[](senderAdapters.length - _excludedAdapters.length);

        // TODO: Consider keeping both senderAdapters and _excludedAdapters sorted lexicographically
        v.adapterLength;
        for (uint256 i; i < senderAdapters.length;) {
            address currAdapter = senderAdapters[i];
            bool excluded = false;
            for (uint256 j; j < _excludedAdapters.length;) {
                if (_excludedAdapters[j] == currAdapter) {
                    excluded = true;
                    break;
                }

                unchecked {
                    ++j;
                }
            }

            if (!excluded) {
                v.adapters[v.adapterLength] = currAdapter;
                ++v.adapterLength;
            }

            unchecked {
                ++i;
            }
        }

        if (v.adapterLength == 0) {
            revert Error.NO_SENDER_ADAPTER_FOUND();
        }

        /// @dev increments nonce
        ++nonce;

        MessageLibrary.Message memory message =
            MessageLibrary.Message(block.chainid, _dstChainId, _target, nonce, _callData, _nativeValue, _expiration);

        v.adapterSuccess = new bool[](v.adapterLength);

        for (uint256 i; i < v.adapterLength;) {
            IBridgeSenderAdapter bridgeAdapter = IBridgeSenderAdapter(v.adapters[i]);

            /// @dev assumes CREATE2 deployment for mma sender & receiver
            uint256 fee = bridgeAdapter.getMessageFee(_dstChainId, mmaReceiver, abi.encode(message));

            /// @dev if one bridge is paused, the flow shouldn't be broken
            try IBridgeSenderAdapter(v.adapters[i]).dispatchMessage{value: fee}(
                _dstChainId, mmaReceiver, abi.encode(message)
            ) {
                v.adapterSuccess[i] = true;
            } catch {
                v.adapterSuccess[i] = false;
                emit ErrorSendMessage(v.adapters[i], message);
            }

            unchecked {
                ++i;
            }
        }

        v.msgId = MessageLibrary.computeMsgId(message);

        /// refund remaining fee
        /// FIXME: add an explicit refund address config
        if (address(this).balance > 0) {
            _safeTransferETH(gac.getRefundAddress(), address(this).balance);
        }

        emit MultiMessageMsgSent(
            v.msgId, nonce, _dstChainId, _target, _callData, _nativeValue, _expiration, v.adapters, v.adapterSuccess
        );
    }

    function _addSenderAdapter(address _senderAdapter) private {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        /// @dev reverts if it finds a duplicate
        _checkDuplicates(_senderAdapter);

        senderAdapters.push(_senderAdapter);
        emit SenderAdapterUpdated(_senderAdapter, true);
    }

    function _removeSenderAdapter(address _senderAdapter) private {
        uint256 lastIndex = senderAdapters.length - 1;

        for (uint256 i; i < senderAdapters.length; ++i) {
            if (senderAdapters[i] == _senderAdapter) {
                if (i < lastIndex) {
                    senderAdapters[i] = senderAdapters[lastIndex];
                }

                senderAdapters.pop();

                emit SenderAdapterUpdated(_senderAdapter, false);
                return;
            }
        }
    }

    /// @dev validates if the sender adapter already exists
    /// @param _senderAdapter is the address of the sender to check
    function _checkDuplicates(address _senderAdapter) internal view {
        uint256 len = senderAdapters.length;

        for (uint256 i; i < len;) {
            if (senderAdapters[i] == _senderAdapter) {
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
