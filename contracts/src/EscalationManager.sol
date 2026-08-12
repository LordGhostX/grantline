// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "./ActionSignature.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {MandateEvaluator} from "./MandateEvaluator.sol";
import {IVaultAuthority, IVaultOwner, MandateRegistry} from "./MandateRegistry.sol";

contract EscalationManager {
    enum Status {
        NONE,
        PENDING,
        APPROVED,
        DENIED,
        EXECUTED
    }

    struct Escalation {
        ActionTypes.ActionPlan plan;
        bytes signature;
        Status status;
        uint64 submittedAt;
    }

    error InvalidEvaluator();
    error EscalationNotFound(bytes32 digest);
    error EscalationAlreadyExists(bytes32 digest);
    error EscalationNotPending(bytes32 digest, Status status);
    error EscalationNotApproved(bytes32 digest, Status status);
    error MandateInactive(uint256 mandateId);
    error NotEscalatable(
        MandateEvaluator.Decision decision,
        MandateEvaluator.FailureCode failureCode
    );
    error NonceAlreadyUsed(uint256 mandateId, address agent, uint256 nonce);
    error NonceNotConsumed(uint256 mandateId, address agent, uint256 nonce);
    error NonceReserved(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        bytes32 digest
    );
    error InvalidVault();
    error NotVaultOwner(address caller);
    error NotVaultAuthority(address caller);

    event EscalationSubmitted(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed agent,
        uint256 nonce,
        uint256 nativeAmount,
        uint256 usdAmount,
        bool usdLimitSkipped,
        uint64 submittedAt
    );
    event EscalationApproved(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed owner,
        uint64 approvedAt
    );
    event EscalationDenied(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed owner,
        uint64 deniedAt
    );
    event EscalationExecuted(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed agent,
        uint256 nonce,
        uint64 executedAt
    );

    MandateEvaluator public immutable evaluator;
    mapping(bytes32 digest => Escalation escalation) private _escalations;
    mapping(uint256 mandateId => mapping(address agent => mapping(uint256 nonce => bytes32 digest)))
        public reservedDigest;

    constructor(address evaluatorAddress) {
        if (
            evaluatorAddress == address(0) || evaluatorAddress.code.length == 0
        ) {
            revert InvalidEvaluator();
        }
        evaluator = MandateEvaluator(evaluatorAddress);
    }

    function submit(
        ActionTypes.ActionPlan calldata plan,
        bytes calldata signature
    ) external returns (bytes32 actionDigest) {
        MandateEvaluator.EvaluationResult memory evaluation = evaluator
            .evaluate(plan, signature);
        if (evaluation.decision != MandateEvaluator.Decision.ESCALATE) {
            revert NotEscalatable(evaluation.decision, evaluation.failureCode);
        }

        actionDigest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
        Status existingStatus = _escalations[actionDigest].status;
        if (existingStatus != Status.NONE) {
            revert EscalationAlreadyExists(actionDigest);
        }

        MandateRegistry registry = evaluator.registry();
        if (registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce)) {
            revert NonceAlreadyUsed(plan.mandateId, plan.agent, plan.nonce);
        }
        bytes32 existingDigest = reservedDigest[plan.mandateId][plan.agent][
            plan.nonce
        ];
        if (existingDigest != bytes32(0)) {
            revert NonceReserved(
                plan.mandateId,
                plan.agent,
                plan.nonce,
                existingDigest
            );
        }

        Escalation storage escalation = _escalations[actionDigest];
        escalation.status = Status.PENDING;
        escalation.submittedAt = uint64(block.timestamp);
        escalation.plan.mandateId = plan.mandateId;
        escalation.plan.agent = plan.agent;
        escalation.plan.nonce = plan.nonce;
        escalation.plan.deadline = plan.deadline;
        for (uint256 index; index < plan.actions.length; index++) {
            escalation.plan.actions.push();
            escalation.plan.actions[index].actionType = plan
                .actions[index]
                .actionType;
            escalation.plan.actions[index].version = plan
                .actions[index]
                .version;
            escalation.plan.actions[index].parameters = plan
                .actions[index]
                .parameters;
        }
        escalation.signature = signature;
        reservedDigest[plan.mandateId][plan.agent][plan.nonce] = actionDigest;

        emit EscalationSubmitted(
            actionDigest,
            plan.mandateId,
            plan.agent,
            plan.nonce,
            evaluation.nativeAmount,
            evaluation.usdAmount,
            evaluation.usdLimitSkipped,
            escalation.submittedAt
        );
    }

    function approve(bytes32 actionDigest) external {
        Escalation storage escalation = _pending(actionDigest);
        MandateRegistry.Mandate memory mandate = evaluator
            .registry()
            .getMandate(escalation.plan.mandateId);
        if (mandate.status != MandateRegistry.MandateStatus.ACTIVE) {
            revert MandateInactive(escalation.plan.mandateId);
        }
        _requireVaultOwner(mandate.vault, msg.sender);

        escalation.status = Status.APPROVED;
        emit EscalationApproved(
            actionDigest,
            escalation.plan.mandateId,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    function deny(bytes32 actionDigest) external {
        Escalation storage escalation = _pending(actionDigest);
        MandateRegistry.Mandate memory mandate = evaluator
            .registry()
            .getMandate(escalation.plan.mandateId);
        _requireVaultOwner(mandate.vault, msg.sender);

        escalation.status = Status.DENIED;
        emit EscalationDenied(
            actionDigest,
            escalation.plan.mandateId,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    function markExecuted(bytes32 actionDigest) external {
        Escalation storage escalation = _escalations[actionDigest];
        if (escalation.status == Status.NONE) {
            revert EscalationNotFound(actionDigest);
        }
        if (escalation.status != Status.APPROVED) {
            revert EscalationNotApproved(actionDigest, escalation.status);
        }

        MandateRegistry.Mandate memory mandate = evaluator
            .registry()
            .getMandate(escalation.plan.mandateId);
        if (mandate.status != MandateRegistry.MandateStatus.ACTIVE) {
            revert MandateInactive(escalation.plan.mandateId);
        }
        _requireVaultAuthority(mandate.vault, msg.sender);
        if (
            !evaluator.registry().nonceUsed(
                escalation.plan.mandateId,
                escalation.plan.agent,
                escalation.plan.nonce
            )
        ) {
            revert NonceNotConsumed(
                escalation.plan.mandateId,
                escalation.plan.agent,
                escalation.plan.nonce
            );
        }

        escalation.status = Status.EXECUTED;
        emit EscalationExecuted(
            actionDigest,
            escalation.plan.mandateId,
            escalation.plan.agent,
            escalation.plan.nonce,
            uint64(block.timestamp)
        );
    }

    function getEscalation(
        bytes32 actionDigest
    ) external view returns (Escalation memory escalation) {
        escalation = _escalations[actionDigest];
        if (escalation.status == Status.NONE) {
            revert EscalationNotFound(actionDigest);
        }
    }

    function statusOf(bytes32 actionDigest) external view returns (Status) {
        return _escalations[actionDigest].status;
    }

    function _pending(
        bytes32 actionDigest
    ) private view returns (Escalation storage escalation) {
        escalation = _escalations[actionDigest];
        if (escalation.status == Status.NONE) {
            revert EscalationNotFound(actionDigest);
        }
        if (escalation.status != Status.PENDING) {
            revert EscalationNotPending(actionDigest, escalation.status);
        }
    }

    function _requireVaultOwner(address vault, address caller) private view {
        if (vault.code.length == 0) revert InvalidVault();

        try IVaultOwner(vault).owner() returns (address vaultOwner) {
            if (vaultOwner != caller) revert NotVaultOwner(caller);
        } catch {
            revert InvalidVault();
        }
    }

    function _requireVaultAuthority(
        address vault,
        address caller
    ) private view {
        if (vault.code.length == 0) revert InvalidVault();

        try IVaultAuthority(vault).authority() returns (
            address vaultAuthority
        ) {
            if (vaultAuthority != caller) revert NotVaultAuthority(caller);
        } catch {
            revert InvalidVault();
        }
    }
}
