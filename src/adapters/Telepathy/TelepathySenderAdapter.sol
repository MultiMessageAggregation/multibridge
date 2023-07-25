// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeSenderAdapter.sol";
import "./interfaces/ITelepathy.sol";
import "../../interfaces/IGAC.sol";

import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "../BaseSenderAdapter.sol";

/// @notice sender adapter for telepathy bridge
contract TelepathySenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter {
    string public constant name = "telepathy";

    ITelepathyRouter public immutable telepathyRouter;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev dstChainId => receiverAdapter
    mapping(uint256 => address) public receiverAdapters;

    /*/////////////////////////////////////////////////////////////////
                            MODIFIERS
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    constructor(address _telepathyRouter, address _gac) {
        telepathyRouter = ITelepathyRouter(_telepathyRouter);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @dev telepathy doesn't have fees and are subsidizing the fees
    function getMessageFee(uint256, address, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    /// @notice sends a message via telepathy router
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        returns (bytes32)
    {
        address receiverAdapter = receiverAdapters[_toChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADPATER();
        }

        bytes32 msgId = _getNewMessageId(_toChainId, _to);
        bytes memory payload = abi.encode(AdapterPayload(msgId, msg.sender, receiverAdapter, _to, _data));

        ITelepathyRouter(telepathyRouter).send(uint32(_toChainId), receiverAdapter, payload);
        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);

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
}
