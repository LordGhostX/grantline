// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "./ActionSignature.sol";
import {ActionTypes} from "./ActionTypes.sol";
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
        MandateEvaluator.FailureCode failureCode,
        uint256 failedActionIndex
    );
    error InvalidEvaluator();
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
        uint256 actionCount
    );

    MandateEvaluator public immutable evaluator;

    constructor(address evaluatorAddress) {
        if (
            evaluatorAddress == address(0) || evaluatorAddress.code.length == 0
        ) {
            revert InvalidEvaluator();
        }
        evaluator = MandateEvaluator(evaluatorAddress);
    }

    function execute(
        Vault vault,
        ActionTypes.ActionPlan calldata plan,
        bytes calldata signature
    ) external returns (bytes32 actionDigest) {
        MandateEvaluator.EvaluationResult memory evaluation = evaluator
            .evaluate(plan, signature);
        if (!evaluation.passed) {
            revert EvaluationDenied(
                evaluation.failureCode,
                evaluation.failedActionIndex
            );
        }

        MandateRegistry.Mandate memory mandate = MandateRegistry(
            address(evaluator.registry())
        ).getMandate(plan.mandateId);
        if (mandate.vault != address(vault)) {
            revert VaultMismatch(mandate.vault, address(vault));
        }

        actionDigest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
        MandateRegistry registry = MandateRegistry(
            address(evaluator.registry())
        );
        if (registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce)) {
            revert NonceAlreadyUsed(plan.mandateId, plan.agent, plan.nonce);
        }
        registry.consumeNonce(plan.mandateId, plan.agent, plan.nonce);

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
            plan.actions.length
        );
    }

    function nonceUsed(
        uint256 mandateId,
        address agent,
        uint256 nonce
    ) external view returns (bool) {
        return
            MandateRegistry(address(evaluator.registry())).nonceUsed(
                mandateId,
                agent,
                nonce
            );
    }

    function _executeAction(
        Vault vault,
        ActionTypes.Action calldata action,
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
