// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "./ActionSignature.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {MandateRegistry} from "./MandateRegistry.sol";

interface IUsdValueProvider {
    function quoteUsd(
        address asset,
        uint256 amount
    ) external view returns (uint256 usdAmount, bool available);
}

contract MandateEvaluator {
    enum Decision {
        ALLOW,
        ESCALATE,
        DENY
    }

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
        NATIVE_AMOUNT_BELOW_MINIMUM,
        NATIVE_AMOUNT_ABOVE_MAXIMUM,
        USD_AMOUNT_OVERFLOW,
        USD_AMOUNT_BELOW_MINIMUM,
        USD_AMOUNT_ABOVE_MAXIMUM,
        USD_VALUATION_UNAVAILABLE,
        PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM
    }

    struct EvaluationResult {
        Decision decision;
        FailureCode failureCode;
        uint256 failedActionIndex;
        uint256 nativeAmount;
        uint256 usdAmount;
        bool usdLimitSkipped;
        uint256 nativeBalanceAfter;
    }

    struct Totals {
        uint256 nativeAmount;
        uint256 usdAmount;
        bool usdLimitSkipped;
        bool usdValuationPresent;
    }

    struct RuleViolations {
        bool nativeMinimum;
        bool nativeMaximum;
        bool usdMinimum;
        bool usdMaximum;
        bool preflightNativeBalance;
    }

    error InvalidRegistry();
    error InvalidUsdValueProvider();

    MandateRegistry public immutable registry;
    IUsdValueProvider public immutable usdValueProvider;
    bool public immutable skipUnavailableUsdValuation;

    constructor(
        address registryAddress,
        address usdValueProviderAddress,
        bool skipUnavailableUsdValuation_
    ) {
        if (registryAddress == address(0) || registryAddress.code.length == 0) {
            revert InvalidRegistry();
        }
        if (
            usdValueProviderAddress == address(0) &&
            !skipUnavailableUsdValuation_
        ) {
            revert InvalidUsdValueProvider();
        }
        if (
            usdValueProviderAddress != address(0) &&
            usdValueProviderAddress.code.length == 0
        ) {
            revert InvalidUsdValueProvider();
        }
        registry = MandateRegistry(registryAddress);
        usdValueProvider = IUsdValueProvider(usdValueProviderAddress);
        skipUnavailableUsdValuation = skipUnavailableUsdValuation_;
    }

    function evaluate(
        ActionTypes.ActionPlan calldata plan,
        bytes calldata signature
    ) external view returns (EvaluationResult memory result) {
        if (plan.mandateId == 0 || plan.mandateId > registry.mandateCount()) {
            return
                _failure(
                    FailureCode.MANDATE_NOT_FOUND,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
        }

        MandateRegistry.Mandate memory mandate = registry.getMandate(
            plan.mandateId
        );
        if (mandate.status != MandateRegistry.MandateStatus.ACTIVE) {
            return
                _failure(
                    FailureCode.MANDATE_INACTIVE,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
        }
        if (!registry.isLineageActive(plan.mandateId)) {
            return
                _failure(
                    FailureCode.MANDATE_INACTIVE,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
        }
        MandateRegistry.MandateRules memory effectiveRules = registry
            .getEffectiveRules(plan.mandateId);
        if (plan.agent != mandate.agent) {
            return
                _failure(
                    FailureCode.AGENT_MISMATCH,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
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
                _failure(
                    FailureCode.INVALID_SIGNATURE,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
        }
        if (plan.deadline != 0 && block.timestamp > plan.deadline) {
            return
                _failure(
                    FailureCode.EXPIRED,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
        }
        if (plan.actions.length == 0) {
            return
                _failure(
                    FailureCode.EMPTY_PLAN,
                    type(uint256).max,
                    0,
                    0,
                    false,
                    0
                );
        }

        (
            bool valid,
            Totals memory totals,
            FailureCode validationFailure,
            uint256 failedActionIndex
        ) = _validatePlan(plan, effectiveRules);
        if (!valid) {
            return
                _failure(
                    validationFailure,
                    failedActionIndex,
                    totals.nativeAmount,
                    totals.usdAmount,
                    totals.usdLimitSkipped,
                    0
                );
        }

        MandateRegistry.PreflightRules memory preflightRules = registry
            .getEffectivePreflightRules(plan.mandateId);
        uint256 currentNativeBalance = mandate.vault.balance;
        uint256 nativeBalanceAfter = currentNativeBalance >= totals.nativeAmount
            ? currentNativeBalance - totals.nativeAmount
            : 0;

        return
            _applyRules(
                effectiveRules,
                preflightRules,
                totals,
                nativeBalanceAfter
            );
    }

    function _validatePlan(
        ActionTypes.ActionPlan calldata plan,
        MandateRegistry.MandateRules memory rules
    )
        private
        view
        returns (
            bool valid,
            Totals memory totals,
            FailureCode failureCode,
            uint256 failedActionIndex
        )
    {
        bool usdLimitEnabled = rules.minUsdAmount != 0 ||
            rules.maxUsdAmount != 0;
        failedActionIndex = type(uint256).max;
        for (uint256 index; index < plan.actions.length; index++) {
            (
                bool actionValid,
                Totals memory updatedTotals,
                FailureCode actionFailure
            ) = _validateAction(plan.actions[index], totals, usdLimitEnabled);
            totals = updatedTotals;
            if (!actionValid) {
                return (false, totals, actionFailure, index);
            }
        }
        return (true, totals, FailureCode.NONE, failedActionIndex);
    }

    function _validateAction(
        ActionTypes.Action calldata action,
        Totals memory currentTotals,
        bool usdLimitEnabled
    )
        private
        view
        returns (bool valid, Totals memory totals, FailureCode failureCode)
    {
        totals = currentTotals;
        if (
            action.version != ActionTypes.TRANSFER_VERSION ||
            action.parameters.length == 0
        ) {
            return (false, totals, FailureCode.INVALID_ACTION);
        }

        if (action.actionType == ActionTypes.ActionType.TRANSFER) {
            if (action.parameters.length != 96) {
                return (false, totals, FailureCode.INVALID_ACTION_PARAMETERS);
            }

            ActionTypes.TransferParameters memory transfer = abi.decode(
                action.parameters,
                (ActionTypes.TransferParameters)
            );
            if (transfer.recipient == address(0)) {
                return (false, totals, FailureCode.INVALID_RECIPIENT);
            }
            if (transfer.amount == 0) {
                return (false, totals, FailureCode.INVALID_AMOUNT);
            }

            if (transfer.asset == address(0)) {
                if (totals.nativeAmount > type(uint256).max - transfer.amount) {
                    return (false, totals, FailureCode.AMOUNT_OVERFLOW);
                }
                totals.nativeAmount += transfer.amount;
            }

            if (usdLimitEnabled) {
                (uint256 actionUsdAmount, bool available) = _quoteUsd(
                    transfer.asset,
                    transfer.amount
                );
                if (!available) {
                    if (!skipUnavailableUsdValuation) {
                        return (
                            false,
                            totals,
                            FailureCode.USD_VALUATION_UNAVAILABLE
                        );
                    }
                    totals.usdLimitSkipped = true;
                } else {
                    if (
                        totals.usdAmount > type(uint256).max - actionUsdAmount
                    ) {
                        return (false, totals, FailureCode.USD_AMOUNT_OVERFLOW);
                    }
                    totals.usdAmount += actionUsdAmount;
                    totals.usdValuationPresent = true;
                }
            }
        }

        return (true, totals, FailureCode.NONE);
    }

    function _applyRules(
        MandateRegistry.MandateRules memory rules,
        MandateRegistry.PreflightRules memory preflightRules,
        Totals memory totals,
        uint256 nativeBalanceAfter
    ) private pure returns (EvaluationResult memory) {
        RuleViolations memory violations = _findRuleViolations(
            rules,
            preflightRules,
            totals,
            nativeBalanceAfter
        );
        bool nativeViolation = violations.nativeMinimum ||
            violations.nativeMaximum;
        bool usdViolation = violations.usdMinimum || violations.usdMaximum;
        FailureCode nativeFailureCode = violations.nativeMinimum
            ? FailureCode.NATIVE_AMOUNT_BELOW_MINIMUM
            : FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM;
        FailureCode usdFailureCode = violations.usdMinimum
            ? FailureCode.USD_AMOUNT_BELOW_MINIMUM
            : FailureCode.USD_AMOUNT_ABOVE_MAXIMUM;

        if (nativeViolation && !rules.escalateNativeAmount) {
            return
                _decision(
                    Decision.DENY,
                    nativeFailureCode,
                    totals,
                    nativeBalanceAfter
                );
        }
        if (usdViolation && !rules.escalateUsdAmount) {
            return
                _decision(
                    Decision.DENY,
                    usdFailureCode,
                    totals,
                    nativeBalanceAfter
                );
        }
        if (
            violations.preflightNativeBalance &&
            !preflightRules.escalateNativeBalance
        ) {
            return
                _decision(
                    Decision.DENY,
                    FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM,
                    totals,
                    nativeBalanceAfter
                );
        }
        if (
            nativeViolation || usdViolation || violations.preflightNativeBalance
        ) {
            return
                _decision(
                    Decision.ESCALATE,
                    nativeViolation ? nativeFailureCode : usdViolation
                        ? usdFailureCode
                        : FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM,
                    totals,
                    nativeBalanceAfter
                );
        }

        return
            _decision(
                Decision.ALLOW,
                FailureCode.NONE,
                totals,
                nativeBalanceAfter
            );
    }

    function _findRuleViolations(
        MandateRegistry.MandateRules memory rules,
        MandateRegistry.PreflightRules memory preflightRules,
        Totals memory totals,
        uint256 nativeBalanceAfter
    ) private pure returns (RuleViolations memory violations) {
        violations.nativeMinimum =
            totals.nativeAmount != 0 &&
            rules.minNativeAmount != 0 &&
            totals.nativeAmount < rules.minNativeAmount;
        violations.nativeMaximum =
            rules.maxNativeAmount != 0 &&
            totals.nativeAmount > rules.maxNativeAmount;
        violations.usdMinimum =
            totals.usdValuationPresent &&
            !totals.usdLimitSkipped &&
            rules.minUsdAmount != 0 &&
            totals.usdAmount < rules.minUsdAmount;
        violations.usdMaximum =
            rules.maxUsdAmount != 0 &&
            totals.usdAmount > rules.maxUsdAmount;
        violations.preflightNativeBalance =
            preflightRules.minNativeBalance != 0 &&
            nativeBalanceAfter < preflightRules.minNativeBalance;
    }

    function _quoteUsd(
        address asset,
        uint256 amount
    ) private view returns (uint256 usdAmount, bool available) {
        if (address(usdValueProvider) == address(0)) {
            return (0, false);
        }

        try usdValueProvider.quoteUsd(asset, amount) returns (
            uint256 quotedUsdAmount,
            bool quoteAvailable
        ) {
            return (quotedUsdAmount, quoteAvailable);
        } catch {
            return (0, false);
        }
    }

    function _failure(
        FailureCode failureCode,
        uint256 actionIndex,
        uint256 nativeAmount,
        uint256 usdAmount,
        bool usdLimitSkipped,
        uint256 nativeBalanceAfter
    ) private pure returns (EvaluationResult memory) {
        return
            EvaluationResult({
                decision: Decision.DENY,
                failureCode: failureCode,
                failedActionIndex: actionIndex,
                nativeAmount: nativeAmount,
                usdAmount: usdAmount,
                usdLimitSkipped: usdLimitSkipped,
                nativeBalanceAfter: nativeBalanceAfter
            });
    }

    function _decision(
        Decision decision,
        FailureCode failureCode,
        Totals memory totals,
        uint256 nativeBalanceAfter
    ) private pure returns (EvaluationResult memory) {
        return
            EvaluationResult({
                decision: decision,
                failureCode: failureCode,
                failedActionIndex: type(uint256).max,
                nativeAmount: totals.nativeAmount,
                usdAmount: totals.usdAmount,
                usdLimitSkipped: totals.usdLimitSkipped,
                nativeBalanceAfter: nativeBalanceAfter
            });
    }
}
