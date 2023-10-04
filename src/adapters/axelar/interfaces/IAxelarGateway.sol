// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

interface IAxelarGateway {
    function callContract(string calldata _destinationChain, string calldata _contractAddress, bytes calldata _payload)
        external;

    function isContractCallApproved(
        bytes32 _commandId,
        string calldata _sourceChain,
        string calldata _sourceAddress,
        address _contractAddress,
        bytes32 _payloadHash
    ) external view returns (bool);

    function validateContractCall(
        bytes32 _commandId,
        string calldata _sourceChain,
        string calldata _sourceAddress,
        bytes32 _payloadHash
    ) external returns (bool);
}
