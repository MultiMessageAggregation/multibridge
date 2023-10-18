// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "forge-std/Test.sol";

/// local imports
import {WormholeReceiverAdapter} from "src/adapters/wormhole/WormholeReceiverAdapter.sol";
import {AxelarReceiverAdapter} from "src/adapters/axelar/AxelarReceiverAdapter.sol";
import {AdapterPayload} from "src/libraries/Types.sol";
import "src/libraries/TypeCasts.sol";
import "src/libraries/Message.sol";
import "src/adapters/axelar/libraries/StringAddressConversion.sol";

/// @notice helper interface of axelar gateway to simulaate approve contract call
interface IAxelarGateway {
    function approveContractCall(bytes calldata params, bytes32 commandId) external;

    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;
}

/// @notice handler for invariant testing receiver bridge adapters
contract BridgeAdapterHandler is Test {
    /// @notice local state
    WormholeReceiverAdapter public wormhole;
    AxelarReceiverAdapter public axelar;

    address public multiBridgeReceiver;
    bytes32 public lastMessageId;
    bytes32 public lastMessageHash;

    uint256 public lastBridge;

    bool public success;

    /// @notice modifier to prank caller
    modifier prank(address _prankster) {
        vm.startPrank(_prankster);
        _;
        vm.stopPrank();
    }

    /// @notice initial setup contracts
    constructor(address _wormhole, address _axelar, address _multiBridgeReceiver) {
        wormhole = WormholeReceiverAdapter(_wormhole);
        axelar = AxelarReceiverAdapter(_axelar);
        multiBridgeReceiver = _multiBridgeReceiver;
    }

    /// @notice helper for wormhole receivers
    function receiveWormholeMessages(
        AdapterPayload memory _payload,
        MessageLibrary.Message memory _data,
        bytes[] memory _vaas,
        bytes32 _deliveryHash
    ) external prank(wormhole.relayer()) {
        success = false;
        vm.assume(_payload.msgId != bytes32(0));

        lastBridge = 1;
        _payload.receiverAdapter = address(wormhole);
        _payload.finalDestination = multiBridgeReceiver;
        _data.dstChainId = 56;
        _data.srcChainId = 1;
        _payload.data = abi.encode(_data);

        lastMessageId = _payload.msgId;
        lastMessageHash = _deliveryHash;
        success = true;

        wormhole.receiveWormholeMessages(
            abi.encode(_payload),
            _vaas,
            TypeCasts.addressToBytes32(wormhole.senderAdapter()),
            wormhole.senderChainId(),
            _deliveryHash
        );
    }

    /// @notice helper for axelar receivers
    function receiveAxelarMessages(
        AdapterPayload memory _payload,
        MessageLibrary.Message memory _data,
        bytes32 _commandId
    ) external prank(address(axelar.gateway())) {
        lastBridge = 2;
        _payload.receiverAdapter = address(axelar);
        _payload.finalDestination = multiBridgeReceiver;

        _data.dstChainId = 56;
        _data.srcChainId = 1;
        _payload.data = abi.encode(_data);

        /// @notice simulating the payload existence on axelar's gateway
        /// @dev helps us bypass NOT_APPROVED_BY_GATEWAY error on axelar adapter
        IAxelarGateway(address(axelar.gateway())).approveContractCall(
            abi.encode(
                "ethereum",
                StringAddressConversion.toString(address(axelar.senderAdapter())),
                address(axelar),
                keccak256(abi.encode(_payload)),
                bytes32(0),
                0
            ),
            _commandId
        );

        lastMessageId = _payload.msgId;
        lastMessageHash = _commandId;
        success = true;

        axelar.execute(
            _commandId,
            axelar.senderChainId(),
            StringAddressConversion.toString(axelar.senderAdapter()),
            abi.encode(_payload)
        );
    }
}
