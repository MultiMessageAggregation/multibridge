// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.17;

import "../../interfaces/IBridgeSenderAdapter.sol";
import "./interfaces/IRouterGateway.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../base/BaseSenderAdapter.sol";

contract RouterSenderAdapter is IBridgeSenderAdapter, Ownable, BaseSenderAdapter {
    /* ========== STATE VARIABLES ========== */

    string public constant name = "router";
    IRouterGateway public immutable routerGateway;

    // dstChainId => receiverAdapter address
    mapping(uint256 => address) public receiverAdapters;

    /* ========== EVENTS ========== */

    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    /* ========== CONSTRUCTOR  ========== */

    constructor(address _routerGateway) {
        routerGateway = IRouterGateway(_routerGateway);
    }

    /* ========== EXTERNAL METHODS ========== */

    function getMessageFee(
        uint256,
        address,
        bytes calldata
    ) external view returns (uint256) {
        return routerGateway.requestToDestDefaultFee();
    }

    function dispatchMessage(
        uint256 _toChainId,
        address _to,
        bytes calldata _data
    ) external payable override returns (bytes32) {
        require(receiverAdapters[_toChainId] != address(0), "no receiver adapter");
        bytes32 msgId = _getNewMessageId(_toChainId, _to);

        Utils.RequestArgs memory requestArgs = Utils.RequestArgs(type(uint64).max, false, Utils.FeePayer.APP);

        Utils.DestinationChainParams memory destChainParams = Utils.DestinationChainParams(
            350000,
            0,
            0,
            Strings.toString(uint256(_toChainId))
        );

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encode(msg.sender, _to, _data, msgId);

        bytes[] memory destContractAddresses = new bytes[](1);
        destContractAddresses[0] = toBytes(receiverAdapters[_toChainId]);

        routerGateway.requestToDest{value: msg.value}(
            requestArgs,
            Utils.AckType.NO_ACK,
            Utils.AckGasParams(0, 0),
            destChainParams,
            Utils.ContractCalls(payloads, destContractAddresses)
        );

        return msgId;
    }

    /* ========== ADMIN METHODS ========== */

    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters)
        external
        override
        onlyOwner
    {
        require(_dstChainIds.length == _receiverAdapters.length, "mismatch length");
        for (uint256 i; i < _dstChainIds.length; ++i) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);
        }
    }

    /* ========== UTILS METHODS ========== */

    function toBytes(address a) public pure returns (bytes memory b) {
        assembly {
            let m := mload(0x40)
            a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
            mstore(0x40, add(m, 52))
            b := m
        }
    }
}
