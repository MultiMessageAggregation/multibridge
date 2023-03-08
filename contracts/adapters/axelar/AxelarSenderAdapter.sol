// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeSenderAdapter.sol";
import "./interfaces/IAxelarChainRegistry.sol";
import "./interfaces/IAxelarGateway.sol";
import "./interfaces/IAxelarGasService.sol";
import "./libs/StringAddressConversion.sol";

interface IMultiBridgeSender {
    function caller() external view returns (address);
}

contract AxelarSenderAdapter is Ownable, IBridgeSenderAdapter {
    IAxelarChainRegistry public axelarChainRegistry;
    IAxelarGateway public gateway;
    IAxelarGasService public gasService;

    // A boolean flat indicating whether the contract has been initialized.
    bool public initialized;

    // default gas limit, can be changed by owner.
    uint32 public gasLimit = 500000;

    // receiver adapter address on dst chain
    mapping(uint256 => address) public receiverAdapters;

    // message nonce
    uint32 public nonce;

    // multiBridgeSender address
    IMultiBridgeSender public multiBridgeSender;

    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);
    event MultiBridgeSenderUpdated(address multiBridgeSender);
    event AxelarChainRegistryUpdated(address axelarChainRegistry);
    event GasLimitUpdated(uint32 gasLimit);

    modifier onlyMultiBridgeSender() {
        require(
            msg.sender == address(multiBridgeSender),
            "not multi-bridge msg sender"
        );
        _;
    }

    constructor(address owner) {
        transferOwnership(owner);
    }

    function init(
        address _chainRegistry,
        address _gasService,
        address _gateway,
        address _multiBridgeSender
    ) external {
        require(!initialized, "already initialized");
        initialized = true;

        axelarChainRegistry = IAxelarChainRegistry(_chainRegistry);
        gasService = IAxelarGasService(_gasService);
        gateway = IAxelarGateway(_gateway);
        multiBridgeSender = IMultiBridgeSender(_multiBridgeSender);
    }

    /**
     * @dev Returns the amount of the native token in wei required by the message bridge for sending a message to the specified chain and contract.
     * @param toChainId The ID of the destination chain.
     * @return The fee amount in wei as a uint256 value.
     */
    function getMessageFee(
        uint256 toChainId,
        address,
        bytes calldata
    ) external view override returns (uint256) {
        return axelarChainRegistry.getFee(toChainId, gasLimit);
    }

    /**
     * @dev Return name of this message bridge.
     */
    function name() external pure override returns (string memory) {
        return "Axelar";
    }

    /**
     * @dev sendMessage sends a message to Axelar.
     * @param toChainId The ID of the destination chain.
     * @param to The address of the contract on the destination chain that will receive the message.
     * @param data The data to be included in the message.
     */
    function dispatchMessage(
        uint256 toChainId,
        address to,
        bytes calldata data
    )
        external
        payable
        override
        onlyMultiBridgeSender
        returns (bytes32 messageId)
    {
        address receiverAdapter = receiverAdapters[toChainId];
        require(receiverAdapter != address(0), "receiver adapter not found");

        // get destination chain name from chain id
        string memory destinationChain = axelarChainRegistry.getChainName(
            toChainId
        );

        // Revert if the destination chain is invalid
        require(
            bytes(destinationChain).length > 0,
            "The given toChainId is not supported"
        );

        // calculate fee for the message
        uint256 fee = IAxelarChainRegistry(axelarChainRegistry).getFee(
            toChainId,
            gasLimit
        );

        // revert if fee is not enough
        require(msg.value >= fee, "insufficient fee");

        // generate message id
        bytes32 msgId = bytes32(uint256(nonce));

        callContract(
            destinationChain,
            StringAddressConversion.toString(receiverAdapter),
            msgId,
            to,
            data
        );

        emit MessageDispatched(msgId, msg.sender, toChainId, to, data);
        nonce++;

        return msgId;
    }

    /**
     * @dev Sends a message to the IAxelarRelayer contract for relaying to the Axelar Network.
     * @param destinationChain The name of the destination chain.
     * @param receiverAdapter The address of the adapter on the destination chain that will receive the message.
     * @param msgId The ID of the message to be relayed.
     * @param multibridgeReceiver The address of the MultibridgeReceiver contract on the destination chain that will receive the message.
     * @param data The bytes data to pass to the contract on the destination chain.
     */
    function callContract(
        string memory destinationChain,
        string memory receiverAdapter,
        bytes32 msgId,
        address multibridgeReceiver,
        bytes calldata data
    ) private {
        // encode payload for receiver adapter
        bytes memory payload = abi.encode(
            msgId,
            address(multiBridgeSender),
            multibridgeReceiver,
            data
        );

        gasService.payNativeGasForContractCall{value: msg.value}(
            address(multiBridgeSender),
            destinationChain,
            receiverAdapter,
            payload,
            multiBridgeSender.caller()
        );

        gateway.callContract(destinationChain, receiverAdapter, payload);
    }

    /**
     * @dev Owner update receiver adapter address on dst chain.
     */
    function updateReceiverAdapter(
        uint256[] calldata _dstChainIds,
        address[] calldata _receiverAdapters
    ) external override onlyOwner {
        require(
            _dstChainIds.length == _receiverAdapters.length,
            "mismatch length"
        );
        for (uint256 i = 0; i < _dstChainIds.length; i++) {
            uint256 id = _dstChainIds[i];
            receiverAdapters[id] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);
        }
    }

    function setMultiBridgeSender(address _multiBridgeSender)
        external
        override
        onlyOwner
    {
        multiBridgeSender = IMultiBridgeSender(_multiBridgeSender);
        emit MultiBridgeSenderUpdated(_multiBridgeSender);
    }

    /**
     * @dev setGasLimit sets the gas limit. the gas limit will be used to calculate the bridge fee.
     * @param _gasLimit is the gas limit.
     */
    function setGasLimit(uint32 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
        emit GasLimitUpdated(_gasLimit);
    }

    /**
     * @dev setAxelarChainRegistry sets the address of AxelarChainRegistry.
     * @param _chainRegistry is the address of AxelarChainRegistry.
     */
    function setAxelarChainRegistry(address _chainRegistry) external onlyOwner {
        axelarChainRegistry = IAxelarChainRegistry(_chainRegistry);
        emit AxelarChainRegistryUpdated(_chainRegistry);
    }
}
