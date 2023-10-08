// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

/// local imports
import "../BaseSenderAdapter.sol";
import "../../interfaces/controllers/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

/// @notice sender adapter for wormhole bridge
contract WormholeSenderAdapter is BaseSenderAdapter {
    /// @notice event emitted when a chain id mapping is updated
    event ChainIDMappingUpdated(uint256 indexed origId, uint16 oldWhId, uint16 newWhId);

    string public constant name = "WORMHOLE";
    IWormholeRelayer public immutable relayer;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    mapping(uint256 => uint16) public chainIdMap;

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _wormholeRelayer, address _gac) BaseSenderAdapter(_gac) {
        if (_wormholeRelayer == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }
        relayer = IWormholeRelayer(_wormholeRelayer);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice sends a message via wormhole relayer
    function dispatchMessage(uint256 _receiverChainId, address _to, bytes calldata _data)
        external
        payable
        override
        onlyMultiBridgeMessageSender
        returns (bytes32 msgId)
    {
        address receiverAdapter = receiverAdapters[_receiverChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADAPTER();
        }

        uint16 wormChainId = chainIdMap[_receiverChainId];

        if (wormChainId == 0) {
            revert Error.INVALID_DST_CHAIN();
        }

        msgId = _getNewMessageId(_receiverChainId, _to);
        bytes memory payload = abi.encode(AdapterPayload(msgId, msg.sender, receiverAdapter, _to, _data));

        relayer.sendPayloadToEvm{value: msg.value}(
            wormChainId,
            receiverAdapter,
            payload,
            /// @dev no receiver value since just passing message
            0,
            senderGAC.msgDeliveryGasLimit()
        );

        emit MessageDispatched(msgId, msg.sender, _receiverChainId, _to, _data);
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
            if (_origIds[i] == 0) {
                revert Error.ZERO_CHAIN_ID();
            }

            uint16 oldWhId = chainIdMap[_origIds[i]];
            chainIdMap[_origIds[i]] = _whIds[i];

            emit ChainIDMappingUpdated(_origIds[i], oldWhId, _whIds[i]);

            unchecked {
                ++i;
            }
        }
    }
}
