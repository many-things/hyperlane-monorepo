// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import "forge-std/console.sol";

// ============ Internal Imports ============
import {IArbitrumMessageHook} from "../interfaces/hooks/IArbitrumMessageHook.sol";
import {ArbitrumISM} from "../isms/native/ArbitrumISM.sol";
import {TypeCasts} from "../libs/TypeCasts.sol";

// ============ External Imports ============
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

/**
 * @title ArbitrumMessageHook
 * @notice Message hook to inform the Arbitrum ISM of messages published through
 * the native Arbitrum bridge.
 */
contract ArbitrumMessageHook is IArbitrumMessageHook {
    // ============ Constants ============

    // Domain of chain on which the arbitrum ISM is deployed
    uint32 public immutable destinationDomain;
    // Arbitrum's inbox used to send messages from L1 -> L2
    IInbox public immutable inbox;

    uint128 internal constant MAX_GAS_LIMIT = 100_000;
    uint128 internal constant MAX_GAS_PRICE = 1e9;

    // ============ Public Storage ============

    // Arbitrum ISM to verify messages
    ArbitrumISM public ism;

    // ============ Constructor ============

    constructor(uint32 _destinationDomain, IInbox _inbox) {
        destinationDomain = _destinationDomain;
        inbox = _inbox;
    }

    // ============ External Functions ============

    /**
     * @notice Sets the arbitrum ISM you want to use to verify messages.
     * @param _ism The address of the arbitrum ISM.
     */
    function setArbitrumISM(address _ism) external {
        require(address(ism) == address(0), "ArbitrumHook: ism already set");
        ism = ArbitrumISM(_ism);
    }

    /**
     * @notice Hook to inform the Arbitrum ISM of messages published through.
     * @notice anyone can call this function, that's why we to send msg.sender
     * @param _destination The destination domain of the message.
     * @param _messageId The message ID.
     * @return gasOverhead The gas overhead for the function call on L2.
     */
    function postDispatch(uint32 _destination, bytes32 _messageId)
        external
        override
        returns (uint256)
    {
        require(
            _destination == destinationDomain,
            "ArbitrumHook: invalid destination domain"
        );
        require(
            address(ism) != address(0),
            "ArbitrumHook: ArbitrumISM not set"
        );

        bytes memory _payload = abi.encodeCall(
            ism.receiveFromHook,
            (_messageId, msg.sender)
        );

        // total gas cost = l1 submission fee + l2 execution cost

        // submission fee as rent to keep message in memory and
        // refunded to l2 address if auto-redeem is successful
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(
            _payload.length,
            0
        );

        uint256 totalGasCost = submissionFee + (MAX_GAS_LIMIT * MAX_GAS_PRICE);

        // require(msg.value >= totalGasCost, "ArbitrumHook: insufficient funds");

        // TODO: check if unaliasing is necessay for contract addresses
        IInbox(inbox).createRetryableTicket{value: totalGasCost}({
            to: address(ism),
            l2CallValue: 0, // no value is transferred to the L2 receiver
            maxSubmissionCost: submissionFee,
            excessFeeRefundAddress: msg.sender, // refund limit x price - execution cost
            callValueRefundAddress: msg.sender, // refund if timeout or cancelled
            gasLimit: MAX_GAS_LIMIT,
            maxFeePerGas: MAX_GAS_PRICE,
            data: _payload
        });

        emit ArbitrumMessagePublished(
            address(ism),
            msg.sender,
            _messageId,
            submissionFee
        );

        return submissionFee;
    }
}