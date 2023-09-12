// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

/// local imports
import "../BaseSenderAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

/// @notice sender adapter for wormhole bridge
contract WormholeSenderAdapter is BaseSenderAdapter {
    string public constant name = "wormhole";
    IWormholeRelayer private immutable relayer;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    mapping(uint256 => uint16) chainIdMap;

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _wormholeRelayer, address _gac) BaseSenderAdapter(_gac) {
        relayer = IWormholeRelayer(_wormholeRelayer);
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
    function setChainIdMap(uint256[] calldata _origIds, uint16[] calldata _whIds) external onlyGlobalOwner {
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

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function getMessageFee(uint256 _toChainId, address, bytes calldata) external view override returns (uint256 fee) {
        /// note: 50000 GAS is commonly used across the MMA; move to some global contract
        (fee,) = relayer.quoteEVMDeliveryPrice(chainIdMap[_toChainId], 0, gac.getGlobalMsgDeliveryGasLimit());
    }
}
