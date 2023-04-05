// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "./interfaces/IAxelarChainRegistry.sol";
import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarExecutable.sol";
import "./libs/StringAddressConversion.sol";

contract AxelarReceiverAdapter is
    Ownable,
    IAxelarExecutable,
    IBridgeReceiverAdapter
{
    mapping(uint256 => address) public senderAdapters;
    mapping(bytes32 => bool) public executeMsgs;
    IAxelarChainRegistry public axelarChainRegistry;
    IAxelarGateway public gateway;

    // A boolean flat indicating whether the contract has been initialized.
    bool public initialized;

    event SenderAdapterUpdated(uint256 srcChainId, address senderAdapter);

    // define revert msg
    error NotAllowedSender();

    constructor(address owner) {
        transferOwnership(owner);
    }

    function init(address _chainRegistry, address _gateway) external {
        require(!initialized, "already initialized");
        initialized = true;

        gateway = IAxelarGateway(_gateway);
        axelarChainRegistry = IAxelarChainRegistry(_chainRegistry);
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external override {
        bytes32 payloadHash = keccak256(payload);

        // Validate the Axelar contract call. This will revert if the call is not approved by the Axelar Gateway contract.
        if (
            !gateway.validateContractCall(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash
            )
        ) revert NotApprovedByGateway();

        // Get the source chain id by chain name
        uint256 srcChainId = axelarChainRegistry.getChainId(sourceChain);

        // Check if the sender is allowed.
        // The sender should be the address of the sender adapter contract on the source chain.
        if (
            StringAddressConversion.toAddress(sourceAddress) !=
            senderAdapters[srcChainId]
        ) revert NotAllowedSender();

        // Decode the payload
        (
            bytes32 msgId,
            address srcSender,
            address destReceiver,
            bytes memory data
        ) = abi.decode(payload, (bytes32, address, address, bytes));

        // Check if the message has been executed
        if (executeMsgs[msgId]) revert MessageIdAlreadyExecuted(msgId);

        // Mark the message as executed
        executeMsgs[msgId] = true;

        // Call MultiBridgeReceiver contract to execute the message
        (bool ok, bytes memory lowLevelData) = destReceiver.call(
            abi.encodePacked(data, msgId, srcChainId, srcSender)
        );

        if (!ok) {
            revert MessageFailure(msgId, lowLevelData);
        } else {
            // Emit the event if the message is executed successfully
            emit MessageIdExecuted(srcChainId, msgId);
        }
    }

    /**
     * @dev Owner update sender adapter address on src chain.
     */
    function updateSenderAdapter(
        uint256[] calldata _srcChainIds,
        address[] calldata _senderAdapters
    ) external onlyOwner {
        // Check the length of the input arrays
        require(
            _srcChainIds.length == _senderAdapters.length,
            "AxelarReceiverAdapter: invalid input"
        );

        // Update the sender adapter address on the source chain
        for (uint256 i = 0; i < _srcChainIds.length; i++) {
            senderAdapters[_srcChainIds[i]] = _senderAdapters[i];

            emit SenderAdapterUpdated(_srcChainIds[i], _senderAdapters[i]);
        }
    }
}
