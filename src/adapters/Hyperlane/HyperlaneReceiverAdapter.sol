// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.9;

/// local imports
import "../../interfaces/IBridgeReceiverAdapter.sol";
import "../../interfaces/IGAC.sol";
import "../../libraries/Error.sol";
import "../../libraries/Types.sol";

import "./interfaces/IMailbox.sol";
import "./interfaces/IMessageRecipient.sol";
import "./interfaces/IInterchainSecurityModule.sol";
import "./libraries/TypeCasts.sol";

/// @notice receiver adapter for hyperlane bridge
contract HyperlaneReceiverAdapter is IBridgeReceiverAdapter, IMessageRecipient, ISpecifiesInterchainSecurityModule {
    IMailbox public immutable mailbox;
    IGAC public immutable gac;

    /*/////////////////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////////////////*/

    /// @dev can override if need
    IInterchainSecurityModule public ism;

    /// @dev adapter deployed to Ethereum
    address public senderAdapter;

    /// @dev tracks the msg id status to prevent replay
    mapping(bytes32 => bool) public executedMessages;

    /**
     * @notice Emitted when the ISM is set.
     * @param module The new ISM for this adapter/recipient.
     */
    event IsmSet(address indexed module);

    /**
     * @notice Emitted when a sender adapter for a source chain is updated.
     * @param srcChainId Source chain identifier.
     * @param senderAdapter Address of the sender adapter.
     */
    event SenderAdapterUpdated(uint256 srcChainId, address senderAdapter);

    /*/////////////////////////////////////////////////////////////////
                                 MODIFIER
    ////////////////////////////////////////////////////////////////*/
    modifier onlyCaller() {
        if (!gac.isPrevilagedCaller(msg.sender)) {
            revert Error.INVALID_PREVILAGED_CALLER();
        }
        _;
    }

    modifier onlyMailbox() {
        if (msg.sender != address(mailbox)) {
            revert Error.CALLER_NOT_HYPERLANE_MAILBOX();
        }
        _;
    }

    /*/////////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////////*/

    /// @param _mailbox is hyperlane's mailbox contract
    constructor(address _mailbox, address _gac) {
        if (_mailbox == address(0)) {
            revert Error.ZERO_MAILBOX_ADDRESS();
        }

        mailbox = IMailbox(_mailbox);
        gac = IGAC(_gac);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @notice set the ism for this adapter/recipient
    /// @param _ism contract address
    /// note: use only if needed
    function setIsm(address _ism) external onlyCaller {
        ism = IInterchainSecurityModule(_ism);
        emit IsmSet(_ism);
    }

    /// @inheritdoc IBridgeReceiverAdapter
    function updateSenderAdapter(address _senderAdapter) external override onlyCaller {
        if (_senderAdapter == address(0)) {
            revert Error.ZERO_ADDRESS_INPUT();
        }

        address oldAdapter = senderAdapter;
        senderAdapter = _senderAdapter;

        emit SenderAdapterUpdated(oldAdapter, _senderAdapter);
    }

    /// @notice Called by Hyperlane `Mailbox` contract on destination chain to receive cross-chain messages.
    /// @dev _origin Source chain domain identifier (not currently used).
    /// @param _sender Address of the sender on the source chain.
    /// @param _body Body of the message.
    function handle(uint32 _origin, bytes32 _sender, bytes memory _body) external onlyMailbox {
        address adapter = TypeCasts.bytes32ToAddress(_sender);
        AdapterPayload memory decodedPayload = abi.decode(_body, (AdapterPayload));

        if (adapter != senderAdapter) {
            revert Error.INVALID_SOURCE_SENDER();
        }

        if (executedMessages[decodedPayload.msgId]) {
            revert MessageIdAlreadyExecuted(decodedPayload.msgId);
        }

        executedMessages[decodedPayload.msgId] = true;

        (bool success, bytes memory returnData) = decodedPayload.finalDestination.call(
            abi.encodePacked(
                decodedPayload.data, decodedPayload.msgId, uint256(_origin), decodedPayload.senderAdapterCaller
            )
        );

        if (!success) {
            revert MessageFailure(decodedPayload.msgId, returnData);
        }

        emit MessageIdExecuted(uint256(_origin), decodedPayload.msgId);
    }

    /*/////////////////////////////////////////////////////////////////
                            EXTERNAL VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISpecifiesInterchainSecurityModule
    function interchainSecurityModule() external view returns (IInterchainSecurityModule) {
        return ism;
    }
}
