// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

/// library imports
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";

/// @notice receiver adapter for wormhole bridge
/// @dev allows wormhole relayers to write to receiver adapter which then forwards the message to
/// the MMA receiver.
contract WormholeReceiverAdapter is IBridgeReceiverAdapter, IWormholeReceiver {
    address public immutable relayer;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    address public senderAdapter;

    mapping(uint256 => uint16) public chainIdMap;
    mapping(uint16 => uint256) public reversechainIdMap;
    mapping(bytes32 => bool) public processedMessages;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
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
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    /// @dev maps the MMA chain id to bridge specific chain id
    /// @dev _origIds is the chain's native chain id
    /// @dev _whIds are the bridge allocated chain id
    function setChainchainIdMap(uint256[] calldata _origIds, uint16[] calldata _whIds) external onlyCaller {
        uint256 arrLength = _origIds.length;

        if (arrLength != _whIds.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < arrLength;) {
            chainIdMap[_origIds[i]] = _whIds[i];
            reversechainIdMap[_whIds[i]] = _origIds[i];

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override onlyRelayerContract {
        (address srcSender, address destReceiver, bytes memory data, address receiverAdapter) =
            abi.decode(payload, (address, address, bytes, address));

        if (receiverAdapter != address(this)) {
            revert Error.RECEIVER_ADAPTER_MISMATCHED();
        }

        if (processedMessages[deliveryHash]) {
            revert MessageIdAlreadyExecuted(deliveryHash);
        } else {
            processedMessages[deliveryHash] = true;
        }

        //send message to destReceiver
        (bool ok, bytes memory lowLevelData) =
            destReceiver.call(abi.encodePacked(data, deliveryHash, uint256(reversechainIdMap[sourceChain]), srcSender));
        if (!ok) {
            revert MessageFailure(deliveryHash, lowLevelData);
        } else {
            emit MessageIdExecuted(reversechainIdMap[sourceChain], deliveryHash);
        }
    }
}
