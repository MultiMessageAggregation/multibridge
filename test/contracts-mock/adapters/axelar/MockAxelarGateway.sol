// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// @dev A mock Axelar gateway that either validates or rejects contract calls
contract MockAxelarGateway {
    bool validate;

    constructor(bool _validate) {
        validate = _validate;
    }

    function validateContractCall(bytes32, string calldata, string calldata, bytes32) external view returns (bool) {
        return validate;
    }
}
