// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IAxelarGateway {
    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external view returns (bool);

    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external;
}
