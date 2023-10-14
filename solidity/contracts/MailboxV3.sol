// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============ Internal Imports ============
import {Versioned} from "./upgrade/Versioned.sol";
import {Message} from "./libs/Message.sol";
import {TypeCasts} from "./libs/TypeCasts.sol";
import {IInterchainSecurityModule, ISpecifiesInterchainSecurityModule} from "./interfaces/IInterchainSecurityModule.sol";
import {IPostDispatchHook} from "./interfaces/hooks/IPostDispatchHook.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipientV3.sol";
import {IMailboxV3} from "./interfaces/IMailboxV3.sol";

// ============ External Imports ============
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MailboxV3 is IMailboxV3, Versioned, Ownable {
    // ============ Libraries ============

    using Message for bytes;
    using TypeCasts for bytes32;
    using TypeCasts for address;

    // ============ Constants ============

    // Domain of chain on which the contract is deployed
    uint32 public immutable localDomain;

    // ============ Public Storage ============

    // A monotonically increasing nonce for outbound unique message IDs.
    uint32 public nonce;

    // The default ISM, used if the recipient fails to specify one.
    IInterchainSecurityModule public defaultIsm;

    // The default post dispatch hook, used for post processing of dispatched messages.
    IPostDispatchHook public defaultHook;

    // Mapping of message ID to whether or not that message has been delivered.
    mapping(bytes32 => bool) public delivered;

    // ============ Events ============

    /**
     * @notice Emitted when the default ISM is updated
     * @param module The new default ISM
     */
    event DefaultIsmSet(address indexed module);

    /**
     * @notice Emitted when the default hook is updated
     * @param hook The new default hook
     */
    event DefaultHookSet(address indexed hook);

    // ============ Constructor ============

    constructor(uint32 _localDomain, address _owner) {
        localDomain = _localDomain;
        _transferOwnership(_owner);
    }

    // ============ External Functions ============

    /**
     * @notice Sets the default ISM for the Mailbox.
     * @param _module The new default ISM. Must be a contract.
     */
    function setDefaultIsm(address _module) external onlyOwner {
        require(Address.isContract(_module), "!contract");
        defaultIsm = IInterchainSecurityModule(_module);
        emit DefaultIsmSet(_module);
    }

    function setDefaultHook(address _hook) external onlyOwner {
        require(Address.isContract(_hook), "!contract");
        defaultHook = IPostDispatchHook(_hook);
        emit DefaultHookSet(_hook);
    }

    /**
     * @notice Dispatches a message to the destination domain & recipient.
     * @param _destinationDomain Domain of destination chain
     * @param _recipientAddress Address of recipient on destination chain as bytes32
     * @param _messageBody Raw bytes content of message body
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 _destinationDomain,
        bytes32 _recipientAddress,
        bytes calldata _messageBody
    ) external payable override returns (bytes32) {
        return
            _dispatch(
                _destinationDomain,
                _recipientAddress,
                _messageBody,
                bytes("")
            );
    }

    /**
     * @notice Dispatches a message to the destination domain & recipient.
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @param hookMetadata Metadata used by the post dispatch hook
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata hookMetadata
    ) external payable override returns (bytes32) {
        return
            _dispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                hookMetadata
            );
    }

    /**
     * @notice Attempts to deliver `_message` to its recipient. Verifies
     * `_message` via the recipient's ISM using the provided `_metadata`.
     * @param _metadata Metadata used by the ISM to verify `_message`.
     * @param _message Formatted Hyperlane message (refer to Message.sol).
     */
    function process(bytes calldata _metadata, bytes calldata _message)
        external
        payable
        override
    {
        // Check that the message was intended for this mailbox.
        require(_message.version() == VERSION, "!version");
        require(_message.destination() == localDomain, "!destination");

        // Check that the message hasn't already been delivered.
        bytes32 _id = _message.id();
        require(delivered[_id] == false, "delivered");

        address recipient = _message.recipientAddress();

        // Verify the message via the ISM.
        IInterchainSecurityModule _ism = IInterchainSecurityModule(
            recipientIsm(recipient)
        );
        require(_ism.verify(_metadata, _message), "!module");

        // effects
        delivered[_id] = true;
        emit Process(_message);
        emit ProcessId(_id);

        // Deliver the message to the recipient. (interactions)
        IMessageRecipient(recipient).handle{value: msg.value}(
            _message.origin(),
            _message.sender(),
            _message.body()
        );
    }

    // ============ Public Functions ============

    /**
     * @notice Returns the ISM to use for the recipient, defaulting to the
     * default ISM if none is specified.
     * @param _recipient The message recipient whose ISM should be returned.
     * @return The ISM to use for `_recipient`.
     */
    function recipientIsm(address _recipient)
        public
        view
        returns (IInterchainSecurityModule)
    {
        // Use a default interchainSecurityModule if one is not specified by the
        // recipient.
        // This is useful for backwards compatibility and for convenience as
        // recipients are not mandated to specify an ISM.
        try
            ISpecifiesInterchainSecurityModule(_recipient)
                .interchainSecurityModule()
        returns (IInterchainSecurityModule _val) {
            // If the recipient specifies a zero address, use the default ISM.
            if (address(_val) != address(0)) {
                return _val;
            }
            // solhint-disable-next-line no-empty-blocks
        } catch {}
        return defaultIsm;
    }

    // ============ Internal Functions ============

    function _dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes memory hookMetadata
    ) internal returns (bytes32) {
        // Format the message into packed bytes.
        bytes memory message = Message.formatMessage(
            VERSION,
            nonce,
            localDomain,
            msg.sender.addressToBytes32(),
            destinationDomain,
            recipientAddress,
            messageBody
        );

        // effects
        nonce += 1;
        bytes32 id = message.id();
        emit DispatchId(id);
        emit Dispatch(message);

        // interactions
        defaultHook.postDispatch{value: msg.value}(hookMetadata, message);
        return id;
    }
}
