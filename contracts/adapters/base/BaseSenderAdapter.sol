// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

abstract contract BaseSenderAdapter {
    uint256 public nonce;

    /**
     * @notice Get new message Id and increment nonce
     * @param _toChainId is the destination chainId.
     * @param _to is the contract address on the destination chain.
     * @param _data is the data to be sent to _to by low-level call(eg. address(_to).call(_data)).
     */

    function _getNewMessageId(
        uint256 _toChainId,
        address _to,
        bytes memory _data
    ) internal returns (bytes32 messageId) {
        bytes32 messageId = keccak256(abi.encodePacked(getChainId(), _toChainId, nonce, address(this), _to, _data));
        nonce++;
    }

    /// @dev Get current chain id
    function getChainId() public view virtual returns (uint256 cid) {
        assembly {
            cid := chainid()
        }
    }
}
