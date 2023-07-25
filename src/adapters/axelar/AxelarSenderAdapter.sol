// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeSenderAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/IAxelarChainRegistry.sol";
import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarGasService.sol";
import "./libraries/StringAddressConversion.sol";

interface IMultiBridgeSender {
    function caller() external view returns (address);
}

contract AxelarSenderAdapter is IBridgeSenderAdapter {
    string public constant name = "axelar";

    IAxelarGateway public immutable gateway;
    IGAC public immutable gac;
    IAxelarChainRegistry public immutable axelarChainRegistry;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    uint32 public nonce;

    IAxelarGasService public gasService;

    /// @dev maps receiver adapter address on dst chain
    mapping(uint256 => address) public receiverAdapters;

    /*/////////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _chainRegistry, address _gasService, address _gateway, address _gac) {
        axelarChainRegistry = IAxelarChainRegistry(_chainRegistry);
        gasService = IAxelarGasService(_gasService);
        gateway = IAxelarGateway(_gateway);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

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


    /// @dev sendMessage sends a message to Axelar.
    /// @param toChainId The ID of the destination chain.
    /// @param to The address of the contract on the destination chain that will receive the message.
    /// @param data The data to be included in the message.
    function dispatchMessage(uint256 toChainId, address to, bytes calldata data)
        external
        payable
        override
        returns (bytes32 messageId)
    {
        address receiverAdapter = receiverAdapters[toChainId];
        
        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADPATER();
        }
        // get destination chain name from chain id
        string memory destinationChain = axelarChainRegistry.getChainName(toChainId);

        // Revert if the destination chain is invalid
        if(bytes(destinationChain).length > 0) {
            revert Error.INVALID_DST_CHAIN();
        }

        // calculate fee for the message
        uint256 fee = IAxelarChainRegistry(axelarChainRegistry).getFee(toChainId, uint32(gac.getGlobalMsgDeliveryGasLimit()));

        // revert if fee is not enough
        if(msg.value < fee) {
            revert Error.INSUFFICIENT_FEES();
        }

        // generate message id
        bytes32 msgId = bytes32(uint256(nonce));

        _callContract(destinationChain, StringAddressConversion.toString(receiverAdapter), msgId, to, data);

        emit MessageDispatched(msgId, msg.sender, toChainId, to, data);
        nonce++;

        return msgId;
    }

    /// @dev Sends a message to the IAxelarRelayer contract for relaying to the Axelar Network.
    /// @param destinationChain The name of the destination chain.
    /// @param receiverAdapter The address of the adapter on the destination chain that will receive the message.
    /// @param msgId The ID of the message to be relayed.
    /// @param multibridgeReceiver The address of the MultibridgeReceiver contract on the destination chain that will receive the message.
    /// @param data The bytes data to pass to the contract on the destination chain.
    function _callContract(
        string memory destinationChain,
        string memory receiverAdapter,
        bytes32 msgId,
        address multibridgeReceiver,
        bytes calldata data
    ) private {
        // encode payload for receiver adapter
        bytes memory payload = abi.encode(msgId, address(msg.sender), multibridgeReceiver, data);

        gasService.payNativeGasForContractCall{value: msg.value}(
            msg.sender, destinationChain, receiverAdapter, payload, msg.sender
        );

        gateway.callContract(destinationChain, receiverAdapter, payload);
    }


    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function getMessageFee(uint256 toChainId, address, bytes calldata) external view override returns (uint256) {
        return axelarChainRegistry.getFee(toChainId, uint32(gac.getGlobalMsgDeliveryGasLimit()));
    }

}
