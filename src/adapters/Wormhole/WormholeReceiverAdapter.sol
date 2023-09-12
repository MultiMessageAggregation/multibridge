/// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "forge-std/console.sol";

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IMultiMessageReceiver.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";
import "../../libraries/TypeCasts.sol";
import "../../libraries/Message.sol";

/// @notice receiver adapter for wormhole bridge
/// @dev allows wormhole relayers to write to receiver adapter which then forwards the message to
/// the MMA receiver.
contract WormholeReceiverAdapter is IBridgeReceiverAdapter, IWormholeReceiver {
    string public constant name = "wormhole";
    address public immutable relayer;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    address public senderAdapter;
    uint16 public senderChain;

    mapping(uint256 => uint16) public chainIdMap;

    mapping(bytes32 => bool) public isMessageExecuted;
    mapping(bytes32 => bool) public deliveryHashStatus;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyGlobalOwner() {
        if (!gac.isGlobalOwner(msg.sender)) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    modifier onlyRelayerContract() {
        if (msg.sender != relayer) {
            revert Error.CALLER_NOT_WORMHOLE_RELAYER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _relayer is wormhole relayer.
    /// @param _gac is global access controller.
    /// note: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/automatic-relayer
    constructor(address _relayer, address _gac) {
        relayer = _relayer;
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external override onlyGlobalOwner {
        uint16 _senderChainDecoded = abi.decode(_senderChain, (uint16));

        if (_senderChainDecoded == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;
        senderChain = _senderChainDecoded;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter, _senderChain);
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

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override onlyRelayerContract {
        /// @dev validate the caller (done in modifier)
        /// @dev step-1: validate incoming chain id
        if (sourceChain != senderChain) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }

        /// @dev step-2: validate the source address
        if (TypeCasts.bytes32ToAddress(sourceAddress) != senderAdapter) {
            console.log(TypeCasts.bytes32ToAddress(sourceAddress));
            console.log(senderAdapter);
            revert Error.INVALID_SENDER_ADAPTER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(payload, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-3: check for duplicate message
        if (isMessageExecuted[msgId] || deliveryHashStatus[deliveryHash]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        isMessageExecuted[decodedPayload.msgId] = true;
        deliveryHashStatus[deliveryHash] = true;

        /// @dev step-4: validate the destination
        if (decodedPayload.finalDestination != gac.getMultiMessageReceiver(block.chainid)) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        MessageLibrary.Message memory _data = abi.decode(decodedPayload.data, (MessageLibrary.Message));

        try IMultiMessageReceiver(decodedPayload.finalDestination).receiveMessage(_data, name) {
            emit MessageIdExecuted(_data.srcChainId, msgId);
        } catch (bytes memory lowLevelData) {
            revert MessageFailure(msgId, lowLevelData);
        }
    }
}
