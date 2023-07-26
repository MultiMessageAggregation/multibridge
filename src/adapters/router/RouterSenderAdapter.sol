// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// library imports
import "openzeppelin-contracts/contracts/utils/Strings.sol";

/// local imports
import "../../interfaces/IBridgeSenderAdapter.sol";
import "./interfaces/IRouterGateway.sol";
import "../../interfaces/IGAC.sol";

import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "../BaseSenderAdapter.sol";

/// @notice sender adapter for router bridge
contract RouterSenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter {
    string public constant name = "router";

    IRouterGateway public immutable routerGateway;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    mapping(uint256 => address) public receiverAdapters;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyMultiMessageSender() {
        if (msg.sender != gac.getMultiMessageSender()) {
            revert Error.CALLER_NOT_MULTI_MESSAGE_SENDER();
        }
        _;
    }

    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    constructor(address _routerGateway, address _gac) {
        routerGateway = IRouterGateway(_routerGateway);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice sends a message via router gateway
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        onlyMultiMessageSender
        returns (bytes32)
    {
        if(_toChainId == 0) {
            revert Error.ZERO_CHAIN_ID();
        }

        address receiverAdapter = receiverAdapters[_toChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADPATER();
        }

        bytes32 msgId = _getNewMessageId(_toChainId, _to);

        Utils.RequestArgs memory requestArgs = Utils.RequestArgs(type(uint64).max, false, Utils.FeePayer.APP);
        Utils.DestinationChainParams memory destChainParams = Utils.DestinationChainParams(
            uint64(gac.getGlobalMsgDeliveryGasLimit()), 0, 0, Strings.toString(uint256(_toChainId))
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

    /// @inheritdoc IBridgeSenderAdapter
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters)
        external
        override
        onlyCaller
    {
        uint256 arrLength = _dstChainIds.length;

        if (arrLength != _receiverAdapters.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < arrLength;) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function toBytes(address a) public pure returns (bytes memory b) {
        assembly {
            let m := mload(0x40)
            a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
            mstore(0x40, add(m, 52))
            b := m
        }
    }

    /*/////////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function getMessageFee(uint256, address, bytes calldata) external view returns (uint256) {
        return routerGateway.requestToDestDefaultFee();
    }
}
