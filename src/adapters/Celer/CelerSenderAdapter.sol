// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../../interfaces/IBridgeSenderAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../BaseSenderAdapter.sol";

import "./interfaces/IMessageBus.sol";

/// @notice sender adapter for celer bridge
contract CelerSenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter {
    string public constant name = "celer";

    IMessageBus public immutable msgBus;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    mapping(uint256 => address) public receiverAdapters;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyMultiMessageSender() {
        if (msg.sender != gac.getMultiMessageSender()) {
            revert Error.CALLER_NOT_MULTI_MESSAGE_SENDER();
        }
        _;
    }

    modifier onlyCaller() {
        if (!gac.isprivilegedCaller(msg.sender)) {
            revert Error.INVALID_PRIVILEGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _msgBus, address _gac) {
        msgBus = IMessageBus(_msgBus);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice sends a message via celer message bus
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        onlyMultiMessageSender
        returns (bytes32 msgId)
    {
        if (_toChainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        address receiverAdapter = receiverAdapters[_toChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        msgId = _getNewMessageId(_toChainId, _to);
        bytes memory payload = abi.encode(AdapterPayload(msgId, msg.sender, receiverAdapter, _to, _data));

        IMessageBus(msgBus).sendMessage{value: msg.value}(receiverAdapter, _toChainId, payload);

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
    }

    /// @inheritdoc IBridgeSenderAdapter
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters)
        external
        override
        onlyCaller
    {
        uint256 arrLength = _dstChainIds.length;

        if (arrLength != _receiverAdapters.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < arrLength;) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function getMessageFee(uint256, address _to, bytes calldata _data) external view override returns (uint256) {
        /// @dev fee is depended only on message length
        return IMessageBus(msgBus).calcFee(abi.encode(bytes32(""), msg.sender, _to, _data));
    }
}
