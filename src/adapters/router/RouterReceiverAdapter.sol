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
    mapping(bytes32 => bool) public executedMessages;

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
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    /// @inheritdoc IRouterReceiver
    function handleRequestFromSource(
        bytes memory srcContractAddress,
        bytes memory payload,
        string memory srcChainId,
        uint64
    ) external override onlyRouterGateway returns (bytes memory) {
        AdapterPayload memory decodedPayload = abi.decode(payload, (AdapterPayload));
        uint256 _srcChainId = StringToUint.st2num(srcChainId);

        if (decodedPayload.receiverAdapter != address(this)) {
            revert Error.RECEIVER_ADAPTER_MISMATCHED();
        }

        if (_toAddress(srcContractAddress) != senderAdapter) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        if (executedMessages[decodedPayload.msgId]) {
            revert MessageIdAlreadyExecuted(decodedPayload.msgId);
        }

        executedMessages[decodedPayload.msgId] = true;

        (bool ok, bytes memory lowLevelData) = decodedPayload.finalDestination.call(
            abi.encodePacked(decodedPayload.data, decodedPayload.msgId, _srcChainId, decodedPayload.senderAdapterCaller)
        );

        if (!ok) {
            revert MessageFailure(decodedPayload.msgId, lowLevelData);
        } else {
            emit MessageIdExecuted(_srcChainId, decodedPayload.msgId);
        }

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
