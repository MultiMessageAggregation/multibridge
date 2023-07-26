// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IMultiMessageReceiver.sol";
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/IRouterGateway.sol";
import "./interfaces/IRouterReceiver.sol";
import "./libraries/StringToUint.sol";

/// @notice receiver adapter for router bridge
contract RouterReceiverAdapter is IRouterReceiver, IBridgeReceiverAdapter {
    IRouterGateway public immutable routerGateway;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    address public senderAdapter;
    string public senderChain;

    mapping(bytes32 => bool) public isMessageExecuted;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    modifier onlyRouterGateway() {
        if (msg.sender != address(routerGateway)) {
            revert Error.CALLER_NOT_ROUTER_GATEWAY();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _routerGateway, address _gac) {
        routerGateway = IRouterGateway(_routerGateway);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(bytes memory _senderChain, address _senderAdapter) external override onlyCaller {
        string memory _senderChainDecoded = abi.decode(_senderChain, (string));

        if (keccak256(abi.encode(_senderChainDecoded)) == keccak256(abi.encode(""))) {
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

    /// @inheritdoc IRouterReceiver
    function handleRequestFromSource(
        bytes memory srcContractAddress,
        bytes memory payload,
        string memory srcChainId,
        uint64
    ) external override onlyRouterGateway returns (bytes memory) {
        /// @dev step-1: validate incoming chain id
        if (keccak256(bytes(srcChainId)) != keccak256(bytes(senderChain))) {
            revert Error.INVALID_SENDER_CHAIN_ID();
        }
        
        /// @dev step-2: validate the caller (done in modifier)

        /// @dev step-3: validate the source address
        if (_toAddress(srcContractAddress) != senderAdapter) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        /// decode the cross-chain payload
        AdapterPayload memory decodedPayload = abi.decode(payload, (AdapterPayload));
        bytes32 msgId = decodedPayload.msgId;

        /// @dev step-4: check for duplicate message
        if (isMessageExecuted[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        }

        /// @dev step-5: validate the destination
        if (decodedPayload.finalDestination != gac.getMultiMessageReceiver()) {
            revert Error.INVALID_FINAL_DESTINATION();
        }

        isMessageExecuted[msgId] = true;

        // (bool ok, bytes memory lowLevelData) = decodedPayload.finalDestination.call(
        //     abi.encodePacked(decodedPayload.data, decodedPayload.msgId, _srcChainId, decodedPayload.senderAdapterCaller)
        // );

        // if (!ok) {
        //     revert MessageFailure(decodedPayload.msgId, lowLevelData);
        // } else {
        //     emit MessageIdExecuted(_srcChainId, decodedPayload.msgId);
        // }

        return "";
    }

    /*/////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev casts bytes to address
    function _toAddress(bytes memory _bytes) internal pure returns (address contractAddress) {
        bytes20 srcTokenAddress;
        assembly {
            srcTokenAddress := mload(add(_bytes, 0x20))
        }
        contractAddress = address(srcTokenAddress);
    }
}
