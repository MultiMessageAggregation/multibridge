// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IBridgeSenderAdapter} from "../../interfaces/IBridgeSenderAdapter.sol";
import {BaseSenderAdapter} from "../base/BaseSenderAdapter.sol";
import {SingleMessageDispatcher} from "../../interfaces/EIP5164/SingleMessageDispatcher.sol";

import {IMailbox} from "./interfaces/IMailbox.sol";
import {TypeCasts} from "./libraries/TypeCasts.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title HyperlaneSenderAdapter implementation.
 * @notice `IBridgeSenderAdapter` implementation that uses Hyperlane as the bridge.
 */
contract HyperlaneSenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter, Ownable {
    /**
     * @notice Name of this message bridge.
     * @dev name() getter will be automatically created by the compiler.
     */
    string public constant name = "hyperlane";

    /// @notice `Mailbox` contract reference.
    IMailbox public immutable mailbox;

    /**
     * @notice Receiver adapter address for each destination chain.
     * @dev dstChainId => receiverAdapter address.
     */
    mapping(uint256 => address) public receiverAdapters;

    /**
     * @notice Domain identifier for each destination chain.
     * @dev dstChainId => dstDomainId.
     */
    mapping(uint256 => uint32) public destinationDomains;

    /**
     * @notice Emitted when a receiver adapter for a destination chain is updated.
     * @param dstChainId Destination chain identifier.
     * @param receiverAdapter Address of the receiver adapter.
     */
    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    /**
     * @notice Emitted when a domain identifier for a destination chain is updated.
     * @param dstChainId Destination chain identifier.
     * @param dstDomainId Destination domain identifier.
     */
    event DestinationDomainUpdated(uint256 dstChainId, uint32 dstDomainId);

    /**
     * @notice HyperlaneSenderAdapter constructor.
     * @param _mailbox Address of the Hyperlane `Mailbox` contract.
     */
    constructor(address _mailbox) {
        if (_mailbox == address(0)) {
            revert Errors.InvalidMailboxZeroAddress();
        }
        mailbox = IMailbox(_mailbox);
    }

    /// @inheritdoc IBridgeSenderAdapter
    /// @dev we narrow mutability (from view to pure) to remove compiler warnings.
    /// @dev unused parameters are added as comments for legibility.
    function getMessageFee(
        uint256 /* toChainId*/,
        address /* to*/,
        bytes calldata /* data*/
    ) external pure override returns (uint256) {
        // Hyperlane fee can't be calculated based on these inputs, we return 0 and leave fee payment to another transaction/agent
        // See https://docs.hyperlane.xyz/docs/build-with-hyperlane/guides/paying-for-interchain-gas
        return 0;
    }

    /// @inheritdoc SingleMessageDispatcher
    function dispatchMessage(
        uint256 _toChainId,
        address _to,
        bytes calldata _data
    ) external payable override returns (bytes32) {
        address receiverAdapter = receiverAdapters[_toChainId]; // read value into memory once
        if (receiverAdapter == address(0)) {
            revert Errors.InvalidAdapterZeroAddress();
        }
        bytes32 msgId = _getNewMessageId(_toChainId, _to);

        // Read destination domain id from mapping
        uint32 dstDomainId = destinationDomains[_toChainId];
        if (dstDomainId == 0) {
            // Fallback to using the chain id if mapping isn't set for destination chain
            dstDomainId = uint32(_toChainId);
        }

        IMailbox(mailbox).dispatch(
            dstDomainId,
            TypeCasts.addressToBytes32(receiverAdapter),
            // Include the source chain id so that the receiver doesn't have to maintain a srcDomainId => srcChainId mapping
            abi.encode(getChainId(), msgId, msg.sender, _to, _data)
        );

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
        return msgId;
    }

    /// @inheritdoc IBridgeSenderAdapter
    function updateReceiverAdapter(
        uint256[] calldata _dstChainIds,
        address[] calldata _receiverAdapters
    ) external override onlyOwner {
        if (_dstChainIds.length != _receiverAdapters.length) {
            revert Errors.MismatchChainsAdaptersLength(_dstChainIds.length, _receiverAdapters.length);
        }
        for (uint256 i; i < _dstChainIds.length; ++i) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);
        }
    }

    /**
     * @notice Updates destination domain identifiers.
     * @param _dstChainIds Destination chain ids array.
     * @param _dstDomainIds Destination domain ids array.
     */
    function updateDestinationDomainIds(
        uint256[] calldata _dstChainIds,
        uint32[] calldata _dstDomainIds
    ) external onlyOwner {
        if (_dstChainIds.length != _dstDomainIds.length) {
            revert Errors.MismatchChainsDomainsLength(_dstChainIds.length, _dstDomainIds.length);
        }
        for (uint256 i; i < _dstChainIds.length; ++i) {
            destinationDomains[_dstChainIds[i]] = _dstDomainIds[i];
            emit DestinationDomainUpdated(_dstChainIds[i], _dstDomainIds[i]);
        }
    }
}
