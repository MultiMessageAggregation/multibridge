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
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev maps dst chainId -> list of bridge sender adapters
    mapping(uint256 => address[]) public senderAdapters;

    /// @dev contract that can use this multi-bridge sender for cross-chain remoteCall
    /// @notice multi message sender is only intended to be used by a single sender (or) application
    address public immutable caller;

    /// @dev nonce for msgId uniqueness
    uint256 public nonce;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    /// @dev is emitted when a cross-chain message is sent
    event MultiMessageMsgSent(
        bytes32 msgId,
        uint256 nonce,
        uint256 dstChainId,
        address target,
        bytes callData,
        uint256 expiration,
        address[] senderAdapters
    );

    /// @dev is emitted when owner updates the sender adapter
    /// @notice add being false indicates removal of the adapter
    event SenderAdapterUpdated(address senderAdapter, bool add);

    /// @dev is emitted if cross-chain message fails
    event ErrorSendMessage(address senderAdapters, MessageLibrary.Message message);

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/

    /// @dev checks if msg.sender is caller configured in the constructor
    modifier onlyCaller() {
        if (msg.sender != caller) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _caller is the previlaged address to interact with MultiMessageSender
    constructor(address _caller, address _gac) {
        caller = _caller;
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

    /// @param _dstChainId is the destination chainId.
    /// @param _target is the contract address on the destination chain.
    /// @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData)).
    /// @param _expiration is the unix time when the message expires, zero means never expire.
    function remoteCall(uint256 _dstChainId, address _target, bytes calldata _callData, uint64 _expiration)
        external
        payable
        onlyCaller
    {
        /// @dev writes to memory for gas saving
        address[] memory adapters = senderAdapters[_dstChainId];
        uint256 adapterLength = adapters.length;

        if (adapterLength == 0) {
            revert Error.NO_SENDER_ADAPTER_FOUND();
        }

        /// @dev increments nonce
        ++nonce;

        MessageLibrary.Message memory message =
            MessageLibrary.Message(_dstChainId, _target, nonce, _callData, _expiration, "");

        for (uint256 i; i < adapterLength;) {
            IBridgeSenderAdapter bridgeAdapter = IBridgeSenderAdapter(adapters[i]);
            message.bridgeName = bridgeAdapter.name();

            /// @dev assumes CREATE2 deployment for mma sender & receiver
            uint256 fee = bridgeAdapter.getMessageFee(_dstChainId, gac.getMultiMessageReceiver(), abi.encode(message));

            /// @dev if one bridge is paused, the flow shouldn't be broken
            try IBridgeSenderAdapter(adapters[i]).dispatchMessage{value: fee}(
                _dstChainId, gac.getMultiMessageReceiver(), abi.encode(message)
            ) {} catch {
                emit ErrorSendMessage(adapters[i], message);
            }

            unchecked {
                ++i;
            }
        }

        bytes32 msgId = MessageLibrary.computeMsgId(message, block.chainid);

        /// refund remaining fee
        /// FIXME: add an explicit refund address config
        if (address(this).balance > 0) {
            _safeTransferETH(msg.sender, address(this).balance);
        }

        emit MultiMessageMsgSent(msgId, nonce, _dstChainId, _target, _callData, _expiration, adapters);
    }

    /// @notice Add bridge sender adapters
    /// @param _chainId is the destination chainId. Use 0 to add default adapers
    /// @param _senderAdapters is the adapter address to add
    function addSenderAdapters(uint256 _chainId, address[] calldata _senderAdapters) external onlyCaller {
        for (uint256 i; i < _senderAdapters.length;) {
            _addSenderAdapter(_chainId, _senderAdapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Remove bridge sender adapters
    /// @param _chainId is the destination chainId. Use 0 to remove default adapers
    /// @param _senderAdapters is the adapter address to remove
    function removeSenderAdapters(uint256 _chainId, address[] calldata _senderAdapters) external onlyCaller {
        for (uint256 i; i < _senderAdapters.length;) {
            _removeSenderAdapter(_chainId, _senderAdapters[i]);

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
        bytes calldata _callData
    ) public view returns (uint256) {
        MessageLibrary.Message memory message = MessageLibrary.Message(_dstChainId, _target, nonce, _callData, 0, "");
        bytes memory data;
        uint256 totalFee;

        uint256 adaptersChainId = 0; // default adapters
        if (senderAdapters[_dstChainId].length > 0) {
            // if different set of adapters are configured for this desitnation chain
            adaptersChainId = _dstChainId;
        }
        address[] storage adapters = senderAdapters[adaptersChainId];
        for (uint256 i; i < adapters.length; ++i) {
            message.bridgeName = IBridgeSenderAdapter(adapters[i]).name();
            data = abi.encodeWithSelector(IMultiMessageReceiver.receiveMessage.selector, message);
            
            uint256 fee =
                IBridgeSenderAdapter(adapters[i]).getMessageFee(uint256(_dstChainId), _multiMessageReceiver, data);
            
            totalFee += fee;
        }
        return totalFee;
    }

    /*/////////////////////////////////////////////////////////////////
                            PRIVATE/INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _addSenderAdapter(uint256 _chainId, address _senderAdapter) private {
        for (uint256 i; i < senderAdapters[_chainId].length; ++i) {
            if (senderAdapters[_chainId][i] == _senderAdapter) {
                return;
            }
        }
        senderAdapters[_chainId].push(_senderAdapter);
        emit SenderAdapterUpdated(_senderAdapter, true);
    }

    function _removeSenderAdapter(uint256 _chainId, address _senderAdapter) private {
        uint256 lastIndex = senderAdapters[_chainId].length - 1;
        for (uint256 i; i < senderAdapters[_chainId].length; ++i) {
            if (senderAdapters[_chainId][i] == _senderAdapter) {
                if (i < lastIndex) {
                    senderAdapters[_chainId][i] = senderAdapters[_chainId][lastIndex];
                }
                senderAdapters[_chainId].pop();
                emit SenderAdapterUpdated(_senderAdapter, false);
                return;
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
