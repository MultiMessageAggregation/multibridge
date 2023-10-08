// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../BaseSenderAdapter.sol";
import "../../interfaces/controllers/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarGasService.sol";
import "./libraries/StringAddressConversion.sol";

contract AxelarSenderAdapter is BaseSenderAdapter {
    /// @notice event emitted when a chain id mapping is updated
    event ChainIDMappingUpdated(uint256 indexed origId, string oldAxlId, string newAxlId);

    string public constant name = "AXELAR";

    IAxelarGateway public immutable gateway;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    IAxelarGasService public immutable gasService;
    mapping(uint256 => string) public chainIdMap;

    /*/////////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/
    constructor(address _gasService, address _gateway, address _gac) BaseSenderAdapter(_gac) {
        if (_gasService == address(0) || _gateway == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        gasService = IAxelarGasService(_gasService);
        gateway = IAxelarGateway(_gateway);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev sendMessage sends a message to Axelar.
    /// @param _receiverChainId The ID of the destination chain.
    /// @param _to The address of the contract on the destination chain that will receive the message.
    /// @param _data The data to be included in the message.
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

        string memory destinationChain = chainIdMap[_receiverChainId];

        if (bytes(destinationChain).length == 0) {
            revert Error.INVALID_DST_CHAIN();
        }

        msgId = _getNewMessageId(_receiverChainId, _to);
        _callContract(destinationChain, receiverAdapter, msgId, _to, _data);

        emit MessageDispatched(msgId, msg.sender, _receiverChainId, _to, _data);
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
            if (_origIds[i] == 0) {
                revert Error.ZERO_CHAIN_ID();
            }

            string memory oldAxlId = chainIdMap[_origIds[i]];
            chainIdMap[_origIds[i]] = _axlIds[i];

            emit ChainIDMappingUpdated(_origIds[i], oldAxlId, _axlIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev Sends a message to the IAxelarRelayer contract for relaying to the Axelar Network.
    /// @param _destinationChain The name of the destination chain.
    /// @param _receiverAdapter The address of the adapter on the destination chain that will receive the message.
    /// @param _msgId The ID of the message to be relayed.
    /// @param _multibridgeReceiver The address of the MultibridgeReceiver contract on the destination chain that will receive the message.
    /// @param _data The bytes data to pass to the contract on the destination chain.
    function _callContract(
        string memory _destinationChain,
        address _receiverAdapter,
        bytes32 _msgId,
        address _multibridgeReceiver,
        bytes calldata _data
    ) internal {
        string memory receiverAdapterInString = StringAddressConversion.toString(_receiverAdapter);
        bytes memory payload =
            abi.encode(AdapterPayload(_msgId, address(msg.sender), _receiverAdapter, _multibridgeReceiver, _data));

        gasService.payNativeGasForContractCall{value: msg.value}(
            msg.sender, _destinationChain, receiverAdapterInString, payload, msg.sender
        );

        gateway.callContract(_destinationChain, receiverAdapterInString, payload);
    }
}
