// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "./ActionSignature.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {MandateRegistry} from "./MandateRegistry.sol";

contract MandateEvaluator {
    enum FailureCode {
        NONE,
        MANDATE_NOT_FOUND,
        MANDATE_INACTIVE,
        AGENT_MISMATCH,
        INVALID_SIGNATURE,
        EXPIRED,
        EMPTY_PLAN,
        INVALID_ACTION,
        INVALID_ACTION_PARAMETERS,
        INVALID_RECIPIENT,
        INVALID_AMOUNT,
        AMOUNT_OVERFLOW,
        TRANSACTION_LIMIT_EXCEEDED
    }

    struct EvaluationResult {
        bool passed;
        FailureCode failureCode;
        uint256 failedActionIndex;
        uint256 nativeAmount;
    }

    error InvalidRegistry();

    MandateRegistry public immutable registry;

    constructor(address registryAddress) {
        if (registryAddress == address(0) || registryAddress.code.length == 0) {
            revert InvalidRegistry();
        }
        registry = MandateRegistry(registryAddress);
    }

    function evaluate(
        ActionTypes.ActionPlan calldata plan,
        bytes calldata signature
    ) external view returns (EvaluationResult memory result) {
        if (plan.mandateId == 0 || plan.mandateId > registry.mandateCount()) {
            return
                _failure(FailureCode.MANDATE_NOT_FOUND, type(uint256).max, 0);
        }

        MandateRegistry.Mandate memory mandate = registry.getMandate(
            plan.mandateId
        );
        if (mandate.status != MandateRegistry.MandateStatus.ACTIVE) {
            return _failure(FailureCode.MANDATE_INACTIVE, type(uint256).max, 0);
        }
        if (plan.agent != mandate.agent) {
            return _failure(FailureCode.AGENT_MISMATCH, type(uint256).max, 0);
        }
        if (
            !ActionSignature.isValid(
                plan,
                address(this),
                block.chainid,
                signature
            )
        ) {
            return
                _failure(FailureCode.INVALID_SIGNATURE, type(uint256).max, 0);
        }
        if (plan.deadline != 0 && block.timestamp > plan.deadline) {
            return _failure(FailureCode.EXPIRED, type(uint256).max, 0);
        }
        if (plan.actions.length == 0) {
            return _failure(FailureCode.EMPTY_PLAN, type(uint256).max, 0);
        }

        uint256 nativeAmount;
        for (uint256 index; index < plan.actions.length; index++) {
            (
                bool valid,
                uint256 updatedNativeAmount,
                FailureCode failureCode
            ) = _validateAction(
                    plan.actions[index],
                    nativeAmount,
                    mandate.transactionLimit
                );
            if (!valid) {
                return _failure(failureCode, index, updatedNativeAmount);
            }
            nativeAmount = updatedNativeAmount;
        }

        return
            EvaluationResult({
                passed: true,
                failureCode: FailureCode.NONE,
                failedActionIndex: type(uint256).max,
                nativeAmount: nativeAmount
            });
    }

    function _validateAction(
        ActionTypes.Action calldata action,
        uint256 currentNativeAmount,
        uint256 transactionLimit
    )
        private
        pure
        returns (bool valid, uint256 nativeAmount, FailureCode failureCode)
    {
        if (action.version == 0 || action.parameters.length == 0) {
            return (false, currentNativeAmount, FailureCode.INVALID_ACTION);
        }

        nativeAmount = currentNativeAmount;
        if (action.actionType == ActionTypes.ActionType.TRANSFER) {
            if (action.parameters.length != 96) {
                return (
                    false,
                    nativeAmount,
                    FailureCode.INVALID_ACTION_PARAMETERS
                );
            }

            ActionTypes.TransferParameters memory transfer = abi.decode(
                action.parameters,
                (ActionTypes.TransferParameters)
            );
            if (transfer.recipient == address(0)) {
                return (false, nativeAmount, FailureCode.INVALID_RECIPIENT);
            }
            if (transfer.amount == 0) {
                return (false, nativeAmount, FailureCode.INVALID_AMOUNT);
            }

            if (transfer.asset == address(0)) {
                if (nativeAmount > type(uint256).max - transfer.amount) {
                    return (false, nativeAmount, FailureCode.AMOUNT_OVERFLOW);
                }
                nativeAmount += transfer.amount;
                if (transactionLimit != 0 && nativeAmount > transactionLimit) {
                    return (
                        false,
                        nativeAmount,
                        FailureCode.TRANSACTION_LIMIT_EXCEEDED
                    );
                }
            }
        }

        return (true, nativeAmount, FailureCode.NONE);
    }

    function _failure(
        FailureCode failureCode,
        uint256 actionIndex,
        uint256 nativeAmount
    ) private pure returns (EvaluationResult memory) {
        return
            EvaluationResult({
                passed: false,
                failureCode: failureCode,
                failedActionIndex: actionIndex,
                nativeAmount: nativeAmount
            });
    }
}
