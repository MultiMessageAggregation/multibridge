// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "forge-std/console.sol";

/// local imports
import "../BaseSenderAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarGasService.sol";
import "./libraries/StringAddressConversion.sol";

interface IMultiBridgeSender {
    function caller() external view returns (address);
}

contract AxelarSenderAdapter is BaseSenderAdapter {
    string public constant name = "axelar";

    IAxelarGateway public immutable gateway;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    IAxelarGasService public gasService;
    mapping(uint256 => string) public chainIdMap;

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _gasService, address _gateway, address _gac) BaseSenderAdapter(_gac) {
        gasService = IAxelarGasService(_gasService);
        gateway = IAxelarGateway(_gateway);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev sendMessage sends a message to Axelar.
    /// @param _toChainId The ID of the destination chain.
    /// @param _to The address of the contract on the destination chain that will receive the message.
    /// @param _data The data to be included in the message.
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

        string memory destinationChain = chainIdMap[_toChainId];

        if (bytes(destinationChain).length <= 0) {
            revert Error.INVALID_DST_CHAIN();
        }

        msgId = _getNewMessageId(_toChainId, _to);
        _callContract(destinationChain, receiverAdapter, msgId, _to, _data);

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
    }

    /// @dev maps the MMA chain id to bridge specific chain id
    /// @dev _origIds is the chain's native chain id
    /// @dev _axlIds are the bridge allocated chain id
    function setChainIdMap(uint256[] calldata _origIds, string[] calldata _axlIds) external onlyGlobalOwner {
        uint256 arrLength = _origIds.length;

        if (arrLength != _axlIds.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < arrLength;) {
            chainIdMap[_origIds[i]] = _axlIds[i];

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function getMessageFee(uint256 _toChainId, address, bytes calldata) external view override returns (uint256) {
        /// FIXME: axelar has no on-chain message fee estimate. should have to overpay and get refund
        return 1 ether;
        // return axelarChainRegistry.getFee(_toChainId, uint32(gac.getGlobalMsgDeliveryGasLimit()));
    }

    /*/////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev Sends a message to the IAxelarRelayer contract for relaying to the Axelar Network.
    /// @param destinationChain The name of the destination chain.
    /// @param receiverAdapter The address of the adapter on the destination chain that will receive the message.
    /// @param msgId The ID of the message to be relayed.
    /// @param multibridgeReceiver The address of the MultibridgeReceiver contract on the destination chain that will receive the message.
    /// @param data The bytes data to pass to the contract on the destination chain.
    function _callContract(
        string memory destinationChain,
        address receiverAdapter,
        bytes32 msgId,
        address multibridgeReceiver,
        bytes calldata data
    ) internal {
        string memory receiverAdapterInString = StringAddressConversion.toString(receiverAdapter);
        bytes memory payload =
            abi.encode(AdapterPayload(msgId, address(msg.sender), receiverAdapter, multibridgeReceiver, data));

        gasService.payNativeGasForContractCall{value: msg.value}(
            msg.sender, destinationChain, receiverAdapterInString, payload, msg.sender
        );

        gateway.callContract(destinationChain, receiverAdapterInString, payload);
    }
}
