// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../interfaces/IGAC.sol";
import "../libraries/Error.sol";
import "../interfaces/IBridgeSenderAdapter.sol";

abstract contract BaseSenderAdapter is IBridgeSenderAdapter {
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    uint256 public nonce;
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

    modifier onlyGlobalOwner() {
        if (!gac.isGlobalOwner(msg.sender)) {
            revert Error.INVALID_PRIVILEGED_CALLER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _gac is the global access control contract
    constructor(address _gac) {
        if (_gac == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    function updateReceiverAdapter(uint256[] calldata _dstChainIds, address[] calldata _receiverAdapters)
        external
        override
        onlyGlobalOwner
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

    /// @notice generates a new message id by incrementing nonce
    /// @param _toChainId is the destination chainId.
    /// @param _to is the contract address on the destination chain.
    function _getNewMessageId(uint256 _toChainId, address _to) internal returns (bytes32 messageId) {
        messageId = keccak256(abi.encodePacked(getChainId(), _toChainId, nonce, address(this), _to));
        ++nonce;
    }

    /// @dev returns the chain id of the deployed adapter
    /// @return cid is the chain identifier
    function getChainId() public view virtual returns (uint256 cid) {
        assembly {
            cid := chainid()
        }
    }
}
