// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/EIP5164/SingleMessageDispatcher.sol";
import "../../interfaces/IBridgeSenderAdapter.sol";
import "../../MultiMessageSender.sol";
import "../BaseSenderAdapter.sol";
import "../../libraries/Error.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Types.sol";

/// bridge specific imports
import "./interfaces/IMailbox.sol";
import "./interfaces/IInterchainGasPaymaster.sol";
import "./libraries/TypeCasts.sol";

/// @notice sender adapter for hyperlane bridge
contract HyperlaneSenderAdapter is IBridgeSenderAdapter, BaseSenderAdapter {
    string public constant name = "hyperlane";

    IMailbox public immutable mailbox;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/
    IInterchainGasPaymaster public igp;

    /// @notice receiver adapter address for each destination chain.
    mapping(uint256 => address) public receiverAdapters;

    /// @notice mapping local chain id to amb specific chain id
    mapping(uint256 => uint32) public chainIdMap;

    /*/////////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////////*/

    /// @dev is emitted when the IGP is set.
    event IgpSet(address indexed paymaster);

    /// @dev is emitted when destination chain is mapped
    event DestinationChainMapped(uint256 dstChainId, uint32 dstDomainId);

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
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

    /// @param _mailbox is hyperlane's mailbox contract
    /// @param _igp is hyperlane's interchain gas paymaster
    constructor(address _mailbox, address _igp, address _gac) {
        if (_mailbox == address(0)) {
            revert Error.ZERO_MAILBOX_ADDRESS();
        }

        mailbox = IMailbox(_mailbox);
        gac = IGAC(_gac);

        _setIgp(_igp);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc SingleMessageDispatcher
    function dispatchMessage(uint256 _toChainId, address _to, bytes calldata _data)
        external
        payable
        override
        returns (bytes32 msgId)
    {
        address receiverAdapter = receiverAdapters[_toChainId];

        if (receiverAdapter == address(0)) {
            revert Error.ZERO_RECEIVER_ADPATER();
        }

        msgId = _getNewMessageId(_toChainId, _to);
        uint32 dstDomainId = _getDestinationDomain(_toChainId);

        if (dstDomainId == 0) {
            revert Error.INVALID_DST_CHAIN();
        }

        bytes memory payload = abi.encode(AdapterPayload(msgId, msg.sender, receiverAdapter, _to, _data));

        bytes32 hyperlaneMsgId =
            IMailbox(mailbox).dispatch(dstDomainId, TypeCasts.addressToBytes32(receiverAdapter), payload);

        try igp.payForGas{value: msg.value}(
            hyperlaneMsgId, dstDomainId, gac.getGlobalMsgDeliveryGasLimit(), MultiMessageSender(msg.sender).caller()
        ) {} catch {}

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
    }

    /// @notice set the IGP for this adapter
    /// @dev calls `_setIgp`
    function setIgp(address _igp) external onlyCaller {
        _setIgp(_igp);
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

    /// @dev maps the MMA chain id to bridge specific chain id (domain)
    /// @param _dstChainIds destination chain ids array.
    /// @param _dstDomainIds destination domain ids array.
    function setChainchainIdMap(uint256[] calldata _dstChainIds, uint32[] calldata _dstDomainIds) external onlyCaller {
        uint256 arrLength = _dstChainIds.length;

        if (arrLength != _dstDomainIds.length) {
            revert Error.ARRAY_LENGTH_MISMATCHED();
        }

        for (uint256 i; i < arrLength;) {
            chainIdMap[_dstChainIds[i]] = _dstDomainIds[i];
            emit DestinationChainMapped(_dstChainIds[i], _dstDomainIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBridgeSenderAdapter
    /// @dev we narrow mutability (from view to pure) to remove compiler warnings.
    /// @dev unused parameters are added as comments for legibility.
    function getMessageFee(uint256 toChainId, address, /* to*/ bytes calldata /* data*/ )
        external
        view
        override
        returns (uint256)
    {
        uint32 dstDomainId = _getDestinationDomain(toChainId);
        /// @dev destination gasAmount is hardcoded to 500k similar to Wormhole implementation
        /// @dev See https://docs.hyperlane.xyz/docs/build-with-hyperlane/guides/paying-for-interchain-gas
        try igp.quoteGasPayment(dstDomainId, 500000) returns (uint256 gasQuote) {
            return gasQuote;
        } catch {
            /// @dev default to zero, MultiMessageSender.estimateTotalMessageFee doesn't expect this function to revert
            return 0;
        }
    }

    /*/////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice Returns destination domain identifier for given destination chain id.
    /// @dev dstDomainId is read from destinationDomains mapping
    /// @dev Returned dstDomainId can be zero, reverting should be handled by consumers if necessary.
    /// @param _dstChainId Destination chain id.
    /// @return destination domain identifier.
    function _getDestinationDomain(uint256 _dstChainId) internal view returns (uint32) {
        return chainIdMap[_dstChainId];
    }

    /// @dev Sets the IGP for this adapter.
    /// @param _igp The IGP contract address.
    function _setIgp(address _igp) internal {
        igp = IInterchainGasPaymaster(_igp);
        emit IgpSet(_igp);
    }
}
