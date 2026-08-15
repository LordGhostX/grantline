// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";
import {IGrantlineContext, IEvaluator, IRegistry} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

interface IUsdValueProvider {
    function quoteUsd(address asset, uint256 amount) external view returns (uint256 usdAmount, bool available);
}

contract MandateEvaluator is Initializable, GrantlineOwnable2StepUpgradeable, UUPSUpgradeable, IEvaluator {
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

    bytes32 public constant EXECUTOR_MODULE = keccak256("EXECUTOR");
    bytes32 public constant ESCALATION_MANAGER_MODULE = keccak256("ESCALATION_MANAGER");

    error InvalidAddress();
    error InvalidRegistry();
    error InvalidUsdValueProvider();
    error NotTrustedCaller(address caller);

    address public grantline;
    address public override registry;
    address public usdValueProvider;
    bool public skipUnavailableUsdValuation;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address grantlineAddress,
        address registryAddress,
        address usdValueProviderAddress,
        bool skipUnavailableUsdValuation_
    ) external initializer {
        if (grantlineAddress == address(0)) revert InvalidAddress();
        if (registryAddress == address(0) || registryAddress.code.length == 0) {
            revert InvalidRegistry();
        }
        if (usdValueProviderAddress == address(0) && !skipUnavailableUsdValuation_) revert InvalidUsdValueProvider();
        if (usdValueProviderAddress != address(0) && usdValueProviderAddress.code.length == 0) {
            revert InvalidUsdValueProvider();
        }

        grantline = grantlineAddress;
        registry = registryAddress;
        usdValueProvider = usdValueProviderAddress;
        skipUnavailableUsdValuation = skipUnavailableUsdValuation_;
        __Ownable_init(grantlineAddress);
        __Ownable2Step_init();
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function evaluate(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest)
        external
        view
        override
        returns (GrantlineTypes.EvaluationResult memory result)
    {
        _onlyTrustedCaller();
        if (digest != IGrantlineContext(grantline).actionDigest(plan)) {
            return _failure(FailureCode.INVALID_SIGNATURE, type(uint256).max, 0, 0, false, 0);
        }

        IRegistry registryContract = IRegistry(registry);
        if (plan.mandateId == 0 || plan.mandateId > registryContract.mandateCount()) {
            return _failure(FailureCode.MANDATE_NOT_FOUND, type(uint256).max, 0, 0, false, 0);
        }

        GrantlineTypes.Mandate memory mandate = registryContract.getMandate(plan.mandateId);
        if (mandate.status != GrantlineTypes.MandateStatus.ACTIVE) {
            return _failure(FailureCode.MANDATE_INACTIVE, type(uint256).max, 0, 0, false, 0);
        }
        if (!registryContract.isLineageActive(plan.mandateId)) {
            return _failure(FailureCode.MANDATE_INACTIVE, type(uint256).max, 0, 0, false, 0);
        }
        GrantlineTypes.MandateRules memory effectiveRules = registryContract.getEffectiveRules(plan.mandateId);

        if (plan.agent != mandate.agent) {
            return _failure(FailureCode.AGENT_MISMATCH, type(uint256).max, 0, 0, false, 0);
        }

        (address signer, ECDSA.RecoverError recoverError, bytes32 recoverErrorArgument) =
            ECDSA.tryRecoverCalldata(digest, signature);
        if (recoverError != ECDSA.RecoverError.NoError || signer != plan.agent || recoverErrorArgument != bytes32(0)) {
            return _failure(FailureCode.INVALID_SIGNATURE, type(uint256).max, 0, 0, false, 0);
        }
        if (plan.deadline != 0 && block.timestamp > plan.deadline) {
            return _failure(FailureCode.EXPIRED, type(uint256).max, 0, 0, false, 0);
        }
        if (plan.actions.length == 0) {
            return _failure(FailureCode.EMPTY_PLAN, type(uint256).max, 0, 0, false, 0);
        }

        return _evaluateValidPlan(plan, effectiveRules, mandate.vault, registryContract);
    }

    function _evaluateValidPlan(
        ActionTypes.ActionPlan calldata plan,
        GrantlineTypes.MandateRules memory effectiveRules,
        address vault,
        IRegistry registryContract
    ) private view returns (GrantlineTypes.EvaluationResult memory) {
        (bool valid, Totals memory totals, FailureCode validationFailure, uint256 failedActionIndex) =
            _validatePlan(plan, effectiveRules);
        if (!valid) {
            return _failure(
                validationFailure, failedActionIndex, totals.nativeAmount, totals.usdAmount, totals.usdLimitSkipped, 0
            );
        }

        GrantlineTypes.PreflightRules memory preflightRules =
            registryContract.getEffectivePreflightRules(plan.mandateId);
        uint256 currentNativeBalance = vault.balance;
        uint256 nativeBalanceAfter =
            currentNativeBalance >= totals.nativeAmount ? currentNativeBalance - totals.nativeAmount : 0;
        return _applyRules(effectiveRules, preflightRules, totals, nativeBalanceAfter);
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

    function _validatePlan(ActionTypes.ActionPlan calldata plan, GrantlineTypes.MandateRules memory rules)
        private
        view
        returns (bool, Totals memory totals, FailureCode, uint256)
    {
        bool usdLimitEnabled = rules.minUsdAmount != 0 || rules.maxUsdAmount != 0;
        uint256 failedActionIndex = type(uint256).max;
        for (uint256 index; index < plan.actions.length; index++) {
            (bool actionValid, Totals memory updatedTotals, FailureCode actionFailure) =
                _validateAction(plan.actions[index], totals, usdLimitEnabled);
            totals = updatedTotals;
            if (!actionValid) return (false, totals, actionFailure, index);
        }
        return (true, totals, FailureCode.NONE, failedActionIndex);
    }

    function _validateAction(ActionTypes.Action calldata action, Totals memory currentTotals, bool usdLimitEnabled)
        private
        view
        returns (bool, Totals memory totals, FailureCode)
    {
        totals = currentTotals;
        if (
            action.actionType != ActionTypes.ActionType.TRANSFER || action.version != ActionTypes.TRANSFER_VERSION
                || action.parameters.length == 0
        ) return (false, totals, FailureCode.INVALID_ACTION);
        if (action.parameters.length != 96) {
            return (false, totals, FailureCode.INVALID_ACTION_PARAMETERS);
        }

        ActionTypes.TransferParameters memory transfer = abi.decode(action.parameters, (ActionTypes.TransferParameters));
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
            (uint256 actionUsdAmount, bool available) = _quoteUsd(transfer.asset, transfer.amount);
            if (!available) {
                if (!skipUnavailableUsdValuation) {
                    return (false, totals, FailureCode.USD_VALUATION_UNAVAILABLE);
                }
                totals.usdLimitSkipped = true;
            } else {
                if (totals.usdAmount > type(uint256).max - actionUsdAmount) {
                    return (false, totals, FailureCode.USD_AMOUNT_OVERFLOW);
                }
                totals.usdAmount += actionUsdAmount;
                totals.usdValuationPresent = true;
            }
        }
        return (true, totals, FailureCode.NONE);
    }

    function _applyRules(
        GrantlineTypes.MandateRules memory rules,
        GrantlineTypes.PreflightRules memory preflightRules,
        Totals memory totals,
        uint256 nativeBalanceAfter
    ) private pure returns (GrantlineTypes.EvaluationResult memory) {
        RuleViolations memory violations = _findRuleViolations(rules, preflightRules, totals, nativeBalanceAfter);
        bool nativeViolation = violations.nativeMinimum || violations.nativeMaximum;
        bool usdViolation = violations.usdMinimum || violations.usdMaximum;
        FailureCode nativeFailureCode = violations.nativeMinimum
            ? FailureCode.NATIVE_AMOUNT_BELOW_MINIMUM
            : FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM;
        FailureCode usdFailureCode =
            violations.usdMinimum ? FailureCode.USD_AMOUNT_BELOW_MINIMUM : FailureCode.USD_AMOUNT_ABOVE_MAXIMUM;

        if (nativeViolation && !rules.escalateNativeAmount) {
            return _decision(Decision.DENY, nativeFailureCode, totals, nativeBalanceAfter);
        }
        if (usdViolation && !rules.escalateUsdAmount) {
            return _decision(Decision.DENY, usdFailureCode, totals, nativeBalanceAfter);
        }
        if (violations.preflightNativeBalance && !preflightRules.escalateNativeBalance) {
            return
                _decision(Decision.DENY, FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM, totals, nativeBalanceAfter);
        }
        if (nativeViolation || usdViolation || violations.preflightNativeBalance) {
            return _decision(
                Decision.ESCALATE,
                nativeViolation
                    ? nativeFailureCode
                    : usdViolation ? usdFailureCode : FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM,
                totals,
                nativeBalanceAfter
            );
        }
        return _decision(Decision.ALLOW, FailureCode.NONE, totals, nativeBalanceAfter);
    }

    function _findRuleViolations(
        GrantlineTypes.MandateRules memory rules,
        GrantlineTypes.PreflightRules memory preflightRules,
        Totals memory totals,
        uint256 nativeBalanceAfter
    ) private pure returns (RuleViolations memory violations) {
        violations.nativeMinimum = totals.nativeAmount != 0 && rules.minNativeAmount != 0
            && totals.nativeAmount < rules.minNativeAmount;
        violations.nativeMaximum = rules.maxNativeAmount != 0 && totals.nativeAmount > rules.maxNativeAmount;
        violations.usdMinimum = totals.usdValuationPresent && !totals.usdLimitSkipped && rules.minUsdAmount != 0
            && totals.usdAmount < rules.minUsdAmount;
        violations.usdMaximum = rules.maxUsdAmount != 0 && totals.usdAmount > rules.maxUsdAmount;
        violations.preflightNativeBalance =
            preflightRules.minNativeBalance != 0 && nativeBalanceAfter < preflightRules.minNativeBalance;
    }

    function _quoteUsd(address asset, uint256 amount) private view returns (uint256 usdAmount, bool available) {
        if (usdValueProvider == address(0)) return (0, false);
        try IUsdValueProvider(usdValueProvider).quoteUsd(asset, amount) returns (
            uint256 quotedUsdAmount, bool quoteAvailable
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
    ) private pure returns (GrantlineTypes.EvaluationResult memory) {
        return GrantlineTypes.EvaluationResult({
            decision: uint8(Decision.DENY),
            failureCode: uint8(failureCode),
            failedActionIndex: actionIndex,
            nativeAmount: nativeAmount,
            usdAmount: usdAmount,
            usdLimitSkipped: usdLimitSkipped,
            nativeBalanceAfter: nativeBalanceAfter
        });
    }

    function _decision(Decision decision, FailureCode failureCode, Totals memory totals, uint256 nativeBalanceAfter)
        private
        pure
        returns (GrantlineTypes.EvaluationResult memory)
    {
        return GrantlineTypes.EvaluationResult({
            decision: uint8(decision),
            failureCode: uint8(failureCode),
            failedActionIndex: type(uint256).max,
            nativeAmount: totals.nativeAmount,
            usdAmount: totals.usdAmount,
            usdLimitSkipped: totals.usdLimitSkipped,
            nativeBalanceAfter: nativeBalanceAfter
        });
    }

    function _onlyTrustedCaller() private view {
        if (
            msg.sender != grantline && msg.sender != IGrantlineContext(grantline).moduleAddress(EXECUTOR_MODULE)
                && msg.sender != IGrantlineContext(grantline).moduleAddress(ESCALATION_MANAGER_MODULE)
        ) revert NotTrustedCaller(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
