// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

import "../libraries/Error.sol";
import "../interfaces/adapters/IMessageSenderAdapter.sol";
import "../controllers/MessageSenderGAC.sol";

abstract contract BaseSenderAdapter is IMessageSenderAdapter {
    MessageSenderGAC public immutable senderGAC;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    uint256 public nonce;
    mapping(uint256 => address) public receiverAdapters;

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyMultiBridgeMessageSender() {
        if (msg.sender != senderGAC.multiBridgeMessageSender()) {
            revert Error.CALLER_NOT_MULTI_MESSAGE_SENDER();
        }
        _;
    }

    modifier onlyGlobalOwner() {
        if (!senderGAC.isGlobalOwner(msg.sender)) {
            revert Error.CALLER_NOT_OWNER();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _senderGAC is the global access control contract
    constructor(address _senderGAC) {
        if (_senderGAC == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        senderGAC = MessageSenderGAC(_senderGAC);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMessageSenderAdapter
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
            address oldReceiver = receiverAdapters[_dstChainIds[i]];
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], oldReceiver, _receiverAdapters[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice generates a new message id by incrementing nonce
    /// @param _receiverChainId is the destination chainId.
    /// @param _to is the contract address on the destination chain.
    function _getNewMessageId(uint256 _receiverChainId, address _to) internal returns (bytes32 messageId) {
        messageId = keccak256(abi.encodePacked(block.chainid, _receiverChainId, nonce, address(this), _to));
        ++nonce;
    }
}
