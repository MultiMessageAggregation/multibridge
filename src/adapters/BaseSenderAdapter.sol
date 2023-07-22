// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

abstract contract BaseSenderAdapter {
    uint256 public nonce;

    /// @notice Get new message Id and increment nonce
    /// @param _toChainId is the destination chainId.
    /// @param _to is the contract address on the destination chain.
    function _getNewMessageId(uint256 _toChainId, address _to) internal returns (bytes32 messageId) {
        messageId = keccak256(abi.encodePacked(getChainId(), _toChainId, nonce, address(this), _to));
        nonce++;
    }

    /// @dev returns the chain id of the deployed adapter
    /// @return cid is the chain identifier
    function getChainId() public view virtual returns (uint256 cid) {
        assembly {
            cid := chainid()
        }
    }
}
