// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

// This should be owned by the microservice that is paying for gas.
interface IAxelarGasService {
    // This is called on the source chain before calling the gateway to execute a remote contract.
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;
}
