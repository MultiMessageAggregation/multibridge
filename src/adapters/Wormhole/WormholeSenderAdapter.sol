// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

/// local imports
import "../BaseSenderAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../../interfaces/IBridgeSenderAdapter.sol";

/// @notice sender adapter for wormhole bridge
contract WormholeSenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter {
    string public constant name = "wormhole";

    IWormholeRelayer private immutable relayer;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    mapping(uint256 => uint16) chainIdMap;
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
    constructor(address _wormholeRelayer, address _gac) {
        relayer = IWormholeRelayer(_wormholeRelayer);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice sends a message via wormhole relayer
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        onlyMultiMessageSender
        returns (bytes32 msgId)
    {
        address receiverAdapter = receiverAdapters[_toChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        uint16 wormChainId = chainIdMap[_toChainId];

        if (wormChainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        msgId = _getNewMessageId(_toChainId, _to);
        bytes memory payload = abi.encode(AdapterPayload(msgId, msg.sender, receiverAdapter, _to, _data));

        relayer.sendPayloadToEvm{value: msg.value}(
            wormChainId,
            receiverAdapter,
            payload,
            0,
            /// @dev no receiver value since just passing message
            gac.getGlobalMsgDeliveryGasLimit()
        );

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
    }

    /// @dev maps the MMA chain id to bridge specific chain id
    /// @dev _origIds is the chain's native chain id
    /// @dev _whIds are the bridge allocated chain id
    function setChainIdMap(uint256[] calldata _origIds, uint16[] calldata _whIds) external onlyCaller {
        uint256 arrLength = _origIds.length;

        if (arrLength != _whIds.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < arrLength;) {
            chainIdMap[_origIds[i]] = _whIds[i];

            unchecked {
                ++i;
            }
        }
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
    function getMessageFee(uint256 _toChainId, address, bytes calldata) external view override returns (uint256 fee) {
        /// note: 50000 GAS is commonly used across the MMA; move to some global contract
        (fee,) = relayer.quoteEVMDeliveryPrice(chainIdMap[_toChainId], 0, gac.getGlobalMsgDeliveryGasLimit());
    }
}
