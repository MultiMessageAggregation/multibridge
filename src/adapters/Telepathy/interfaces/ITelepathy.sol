// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev imported from (https://github.com/succinctlabs/telepathy-contracts)
interface ITelepathyRouter {
    event SentMessage(uint64 indexed nonce, bytes32 indexed msgHash, bytes message);

    function send(uint32 destinationChainId, bytes32 destinationAddress, bytes calldata data)
        external
        returns (bytes32);

    function send(uint32 destinationChainId, address destinationAddress, bytes calldata data)
        external
        returns (bytes32);

    function sendViaStorage(uint32 destinationChainId, bytes32 destinationAddress, bytes calldata data)
        external
        returns (bytes32);

    function sendViaStorage(uint32 destinationChainId, address destinationAddress, bytes calldata data)
        external
        returns (bytes32);
}

interface ITelepathyReceiver {
    event ExecutedMessage(
        uint32 indexed sourceChainId, uint64 indexed nonce, bytes32 indexed msgHash, bytes message, bool status
    );

    function executeMessage(
        uint64 slot,
        bytes calldata message,
        bytes[] calldata accountProof,
        bytes[] calldata storageProof
    ) external;

    function executeMessageFromLog(
        bytes calldata srcSlotTxSlotPack,
        bytes calldata messageBytes,
        bytes32[] calldata receiptsRootProof,
        bytes32 receiptsRoot,
        bytes[] calldata receiptProof, // receipt proof against receipt root
        bytes memory txIndexRLPEncoded,
        uint256 logIndex
    ) external;
}

interface ITelepathyHandler {
    function handleTelepathy(uint32 _sourceChainId, address _sourceAddress, bytes memory _data)
        external
        returns (bytes4);
}
