// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "./ActionSignature.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {EscalationManager} from "./EscalationManager.sol";
import {MandateEvaluator} from "./MandateEvaluator.sol";
import {MandateRegistry} from "./MandateRegistry.sol";
import {Vault} from "./Vault.sol";

interface IERC20TransferLike {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract VaultExecutor {
    error ActionExecutionFailed(uint256 actionIndex);
    error EvaluationDenied(
        MandateEvaluator.Decision decision,
        MandateEvaluator.FailureCode failureCode,
        uint256 failedActionIndex
    );
    error InvalidEvaluator();
    error InvalidEscalationManager();
    error EscalationNotApproved(
        bytes32 actionDigest,
        EscalationManager.Status status
    );
    error EscalationNonceReserved(bytes32 actionDigest);
    error InvalidTokenTarget(address token);
    error NonceAlreadyUsed(uint256 mandateId, address agent, uint256 nonce);
    error UnsupportedAction(ActionTypes.ActionType actionType);
    error UnsupportedActionVersion(uint8 version);
    error VaultMismatch(address expectedVault, address providedVault);

    event ActionPlanExecuted(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed agent,
        address vault,
        uint256 nonce,
        uint256 nativeAmount,
        uint256 usdAmount,
        bool usdLimitSkipped,
        uint256 actionCount,
        uint256 nativeBalanceAfter
    );

    MandateEvaluator public immutable evaluator;
    EscalationManager public immutable escalationManager;

    constructor(address evaluatorAddress, address escalationManagerAddress) {
        if (
            evaluatorAddress == address(0) || evaluatorAddress.code.length == 0
        ) {
            revert InvalidEvaluator();
        }
        if (
            escalationManagerAddress == address(0) ||
            escalationManagerAddress.code.length == 0
        ) {
            revert InvalidEscalationManager();
        }
        try EscalationManager(escalationManagerAddress).evaluator() returns (
            MandateEvaluator configuredEvaluator
        ) {
            if (address(configuredEvaluator) != evaluatorAddress) {
                revert InvalidEscalationManager();
            }
        } catch {
            revert InvalidEscalationManager();
        }

        evaluator = MandateEvaluator(evaluatorAddress);
        escalationManager = EscalationManager(escalationManagerAddress);
    }

    function execute(
        Vault vault,
        ActionTypes.ActionPlan calldata plan,
        bytes calldata signature
    ) external returns (bytes32 actionDigest) {
        MandateEvaluator.EvaluationResult memory evaluation = evaluator
            .evaluate(plan, signature);
        if (evaluation.decision != MandateEvaluator.Decision.ALLOW) {
            revert EvaluationDenied(
                evaluation.decision,
                evaluation.failureCode,
                evaluation.failedActionIndex
            );
        }

        MandateRegistry.Mandate memory mandate = _registry().getMandate(
            plan.mandateId
        );
        if (mandate.vault != address(vault)) {
            revert VaultMismatch(mandate.vault, address(vault));
        }

        actionDigest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
        _requireUnreservedNonce(plan);
        _executePlan(vault, plan, evaluation, actionDigest, false);
    }

    function executeEscalated(
        bytes32 actionDigest
    ) external returns (bytes32 executedDigest) {
        EscalationManager.Escalation memory escalation = escalationManager
            .getEscalation(actionDigest);
        if (escalation.status != EscalationManager.Status.APPROVED) {
            revert EscalationNotApproved(actionDigest, escalation.status);
        }

        MandateEvaluator.EvaluationResult memory evaluation = evaluator
            .evaluate(escalation.plan, escalation.signature);
        if (evaluation.decision == MandateEvaluator.Decision.DENY) {
            revert EvaluationDenied(
                evaluation.decision,
                evaluation.failureCode,
                evaluation.failedActionIndex
            );
        }

        MandateRegistry.Mandate memory mandate = _registry().getMandate(
            escalation.plan.mandateId
        );
        Vault vault = Vault(payable(mandate.vault));
        executedDigest = ActionSignature.digest(
            escalation.plan,
            address(evaluator),
            block.chainid
        );
        if (executedDigest != actionDigest) {
            revert EscalationNotApproved(actionDigest, escalation.status);
        }

        _executePlan(vault, escalation.plan, evaluation, executedDigest, true);
        escalationManager.markExecuted(actionDigest);
    }

    function nonceUsed(
        uint256 mandateId,
        address agent,
        uint256 nonce
    ) external view returns (bool) {
        return _registry().nonceUsed(mandateId, agent, nonce);
    }

    function _executePlan(
        Vault vault,
        ActionTypes.ActionPlan memory plan,
        MandateEvaluator.EvaluationResult memory evaluation,
        bytes32 actionDigest,
        bool consumeReservation
    ) private {
        MandateRegistry registry = _registry();
        if (registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce)) {
            revert NonceAlreadyUsed(plan.mandateId, plan.agent, plan.nonce);
        }
        if (consumeReservation) {
            registry.consumeReservedNonce(
                plan.mandateId,
                plan.agent,
                plan.nonce,
                actionDigest
            );
        } else {
            registry.consumeNonce(plan.mandateId, plan.agent, plan.nonce);
        }

        for (uint256 index; index < plan.actions.length; index++) {
            _executeAction(vault, plan.actions[index], index);
        }

        emit ActionPlanExecuted(
            actionDigest,
            plan.mandateId,
            plan.agent,
            address(vault),
            plan.nonce,
            evaluation.nativeAmount,
            evaluation.usdAmount,
            evaluation.usdLimitSkipped,
            plan.actions.length,
            evaluation.nativeBalanceAfter
        );
    }

    function _requireUnreservedNonce(
        ActionTypes.ActionPlan calldata plan
    ) private view {
        bytes32 reserved = _registry().reservedDigest(
            plan.mandateId,
            plan.agent,
            plan.nonce
        );
        if (reserved != bytes32(0)) {
            revert EscalationNonceReserved(reserved);
        }
    }

    function _registry() private view returns (MandateRegistry) {
        return MandateRegistry(address(evaluator.registry()));
    }

    function _executeAction(
        Vault vault,
        ActionTypes.Action memory action,
        uint256 actionIndex
    ) private {
        if (action.actionType != ActionTypes.ActionType.TRANSFER) {
            revert UnsupportedAction(action.actionType);
        }
        if (action.version != ActionTypes.TRANSFER_VERSION) {
            revert UnsupportedActionVersion(action.version);
        }

        ActionTypes.TransferParameters memory transfer = abi.decode(
            action.parameters,
            (ActionTypes.TransferParameters)
        );

        if (transfer.asset == address(0)) {
            (bool nativeSuccess, ) = vault.execute(
                transfer.recipient,
                transfer.amount,
                ""
            );
            if (!nativeSuccess) revert ActionExecutionFailed(actionIndex);
            return;
        }

        if (transfer.asset.code.length == 0) {
            revert InvalidTokenTarget(transfer.asset);
        }

        (bool tokenSuccess, bytes memory result) = vault.execute(
            transfer.asset,
            0,
            abi.encodeWithSelector(
                IERC20TransferLike.transfer.selector,
                transfer.recipient,
                transfer.amount
            )
        );
        if (!tokenSuccess || !_tokenTransferSucceeded(result)) {
            revert ActionExecutionFailed(actionIndex);
        }
    }

    function _tokenTransferSucceeded(
        bytes memory result
    ) private pure returns (bool) {
        if (result.length == 0) return true;
        if (result.length != 32) return false;
        return abi.decode(result, (bool));
    }
}
