// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./interfaces/IBridgeSenderAdapter.sol";
import "./interfaces/IMultiMessageReceiver.sol";
import "./MessageStruct.sol";

contract MultiMessageSender {
    // dst chainId -> list of bridge sender adapters
    // index 0 stores the default adapters to be used if senderAdapters[dstChainId] is empty
    mapping(uint256 => address[]) public senderAdapters;

    // The dApp contract that can use this multi-bridge sender for cross-chain remoteCall.
    // This means the current MultiMessageSender is only intended to be used by a single dApp.
    address public immutable caller;
    uint32 public nonce;

    event MultiMessageMsgSent(
        bytes32 msgId,
        uint32 nonce,
        uint64 dstChainId,
        address target,
        bytes callData,
        uint64 expiration,
        address[] senderAdapters
    );
    event SenderAdapterUpdated(address senderAdapter, bool add); // add being false indicates removal of the adapter
    event ErrorSendMessage(address senderAdapters, MessageStruct.Message message);

    modifier onlyCaller() {
        require(msg.sender == caller, "not caller");
        _;
    }

    constructor(address _caller) {
        caller = _caller;
    }

    /**
     * @notice Call a remote function on a destination chain by sending multiple copies of a cross-chain message
     * via all available bridges.
     *
     * A fee in native token may be required by each message bridge to send messages. Any native token fee remained
     * will be refunded back to msg.sender, which requires caller being able to receive native token.
     * Caller can use estimateTotalMessageFee() to get total message fees before calling this function.
     *
     * @param _dstChainId is the destination chainId.
     * @param _multiMessageReceiver is the MultiMessageReceiver address on destination chain.
     * @param _target is the contract address on the destination chain.
     * @param _callData is the data to be sent to _target by low-level call(eg. address(_target).call(_callData)).
     * @param _expiration is the unix time when the message expires, zero means never expire.
     */
    function remoteCall(
        uint64 _dstChainId,
        address _multiMessageReceiver,
        address _target,
        bytes calldata _callData,
        uint64 _expiration
    ) external payable onlyCaller {
        MessageStruct.Message memory message =
            MessageStruct.Message(_dstChainId, nonce, _target, _callData, _expiration, "");
        bytes memory data;
        uint256 totalFee;

        uint256 adaptersChainId = 0; // default adapters
        if (senderAdapters[_dstChainId].length > 0) {
            // if different set of adapters are configured for this desitnation chain
            adaptersChainId = _dstChainId;
        }
        address[] storage adapters = senderAdapters[adaptersChainId];
        // send copies of the message through multiple bridges
        for (uint256 i; i < adapters.length; ++i) {
            message.bridgeName = IBridgeSenderAdapter(adapters[i]).name();
            data = abi.encodeWithSelector(IMultiMessageReceiver.receiveMessage.selector, message);
            uint256 fee =
                IBridgeSenderAdapter(adapters[i]).getMessageFee(uint256(_dstChainId), _multiMessageReceiver, data);
            // if one bridge is paused it shouldn't halt the process
            try IBridgeSenderAdapter(adapters[i]).dispatchMessage{value: fee}(
                uint256(_dstChainId), _multiMessageReceiver, data
            ) {
                totalFee += fee;
            } catch {
                emit ErrorSendMessage(adapters[i], message);
            }
        }
        bytes32 msgId = MessageStruct.computeMsgId(message, uint64(block.chainid));
        emit MultiMessageMsgSent(msgId, nonce, _dstChainId, _target, _callData, _expiration, adapters);
        nonce++;
        // refund remaining native token to msg.sender
        if (totalFee < msg.value) {
            _safeTransferETH(msg.sender, msg.value - totalFee);
        }
    }

    /**
     * @notice Add bridge sender adapters
     * @param _chainId is the destination chainId. Use 0 to add default adapers
     * @param _senderAdapters is the adapter address to add
     */
    function addSenderAdapters(uint256 _chainId, address[] calldata _senderAdapters) external onlyCaller {
        for (uint256 i; i < _senderAdapters.length; ++i) {
            _addSenderAdapter(_chainId, _senderAdapters[i]);
        }
    }

    /**
     * @notice Remove bridge sender adapters
     * @param _chainId is the destination chainId. Use 0 to remove default adapers
     * @param _senderAdapters is the adapter address to remove
     */
    function removeSenderAdapters(uint256 _chainId, address[] calldata _senderAdapters) external onlyCaller {
        for (uint256 i; i < _senderAdapters.length; ++i) {
            _removeSenderAdapter(_chainId, _senderAdapters[i]);
        }
    }

    /**
     * @notice A helper function for estimating total required message fee by all available message bridges.
     */
    function estimateTotalMessageFee(
        uint64 _dstChainId,
        address _multiMessageReceiver,
        address _target,
        bytes calldata _callData
    ) public view returns (uint256) {
        MessageStruct.Message memory message = MessageStruct.Message(_dstChainId, nonce, _target, _callData, 0, "");
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

    /*
     * @dev transfer ETH to an address, revert if it fails.
     * @param to recipient of the transfer
     * @param value the amount to send
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "safeTransferETH: ETH transfer failed");
    }
}
