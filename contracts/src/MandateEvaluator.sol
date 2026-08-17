// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";
import {IChainlinkAggregatorV3, IGrantlineContext, IEvaluator, IRegistry, ISwapAdapter, IVault} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

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
        NATIVE_USD_VALUE_BELOW_MINIMUM,
        NATIVE_USD_VALUE_ABOVE_MAXIMUM,
        NATIVE_USD_VALUATION_UNAVAILABLE,
        PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM,
        MANDATE_PAUSED,
        VAULT_PAUSED,
        MANDATE_NOT_YET_VALID,
        MANDATE_EXPIRED,
        SWAP_UNSUPPORTED,
        INVALID_SWAP_PARAMETERS,
        INVALID_SWAP_ROUTE,
        SWAP_DEADLINE_EXPIRED
    }

    bytes32 public constant EXECUTOR_MODULE = keccak256("EXECUTOR");
    bytes32 public constant ESCALATION_MANAGER_MODULE = keccak256("ESCALATION_MANAGER");
    uint8 public constant MAX_CHAINLINK_FEED_DECIMALS = 18;

    error InvalidAddress();
    error InvalidRegistry();
    error InvalidNativeUsdConfiguration();
    error NotTrustedCaller(address caller);

    address public grantline;
    address public override registry;
    address public override chainlinkNativeUsdFeed;
    uint8 public override chainlinkNativeUsdFeedDecimals;
    address public override wrappedNative;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address grantlineAddress,
        address registryAddress,
        address chainlinkNativeUsdFeedAddress,
        uint8 chainlinkNativeUsdFeedDecimals_,
        address wrappedNativeAddress,
        address moduleOwnerAddress
    ) external initializer {
        if (grantlineAddress == address(0)) revert InvalidAddress();
        if (moduleOwnerAddress == address(0) || moduleOwnerAddress.code.length == 0) revert InvalidAddress();
        if (registryAddress == address(0) || registryAddress.code.length == 0) {
            revert InvalidRegistry();
        }
        _validateNativeUsdConfiguration(
            chainlinkNativeUsdFeedAddress, chainlinkNativeUsdFeedDecimals_, wrappedNativeAddress
        );
        grantline = grantlineAddress;
        registry = registryAddress;
        chainlinkNativeUsdFeed = chainlinkNativeUsdFeedAddress;
        chainlinkNativeUsdFeedDecimals = chainlinkNativeUsdFeedDecimals_;
        wrappedNative = wrappedNativeAddress;
        __Ownable_init(moduleOwnerAddress);
        __Ownable2Step_init();
    }

    function nativeUsdValuationEnabled() public view override returns (bool) {
        return chainlinkNativeUsdFeed != address(0);
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.EVALUATOR;
    }

    function evaluate(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest)
        external
        view
        override
        returns (GrantlineTypes.EvaluationResult memory result)
    {
        _onlyTrustedCaller();
        if (digest != IGrantlineContext(grantline).actionDigest(plan)) {
            return _failure(FailureCode.INVALID_SIGNATURE, type(uint256).max, 0, 0, 0);
        }

        IRegistry registryContract = IRegistry(registry);
        if (plan.mandateId == 0 || plan.mandateId > registryContract.mandateCount()) {
            return _failure(FailureCode.MANDATE_NOT_FOUND, type(uint256).max, 0, 0, 0);
        }

        GrantlineTypes.Mandate memory mandate = registryContract.getMandate(plan.mandateId);
        if (mandate.status == GrantlineTypes.MandateStatus.PAUSED) {
            return _failure(FailureCode.MANDATE_PAUSED, type(uint256).max, 0, 0, 0);
        }
        if (mandate.status != GrantlineTypes.MandateStatus.ACTIVE) {
            return _failure(FailureCode.MANDATE_INACTIVE, type(uint256).max, 0, 0, 0);
        }
        if (!registryContract.isLineageActive(plan.mandateId)) {
            if (registryContract.isLineagePaused(plan.mandateId)) {
                return _failure(FailureCode.MANDATE_PAUSED, type(uint256).max, 0, 0, 0);
            }
            if (registryContract.isLineageRevoked(plan.mandateId)) {
                return _failure(FailureCode.MANDATE_INACTIVE, type(uint256).max, 0, 0, 0);
            }
            (uint64 validAfter, uint64 validUntil) = registryContract.getEffectiveValidityWindow(plan.mandateId);
            if (validAfter != 0 && block.timestamp < validAfter) {
                return _failure(FailureCode.MANDATE_NOT_YET_VALID, type(uint256).max, 0, 0, 0);
            }
            if (validUntil != 0 && block.timestamp > validUntil) {
                return _failure(FailureCode.MANDATE_EXPIRED, type(uint256).max, 0, 0, 0);
            }
            return _failure(FailureCode.MANDATE_INACTIVE, type(uint256).max, 0, 0, 0);
        }
        if (IVault(mandate.vault).paused()) {
            return _failure(FailureCode.VAULT_PAUSED, type(uint256).max, 0, 0, 0);
        }
        GrantlineTypes.MandateRules memory effectiveRules = registryContract.getEffectiveRules(plan.mandateId);

        if (plan.agent != mandate.agent) {
            return _failure(FailureCode.AGENT_MISMATCH, type(uint256).max, 0, 0, 0);
        }

        (address signer, ECDSA.RecoverError recoverError, bytes32 recoverErrorArgument) =
            ECDSA.tryRecoverCalldata(digest, signature);
        if (recoverError != ECDSA.RecoverError.NoError || signer != plan.agent || recoverErrorArgument != bytes32(0)) {
            return _failure(FailureCode.INVALID_SIGNATURE, type(uint256).max, 0, 0, 0);
        }
        if (plan.deadline != 0 && block.timestamp > plan.deadline) {
            return _failure(FailureCode.EXPIRED, type(uint256).max, 0, 0, 0);
        }
        if (plan.actions.length == 0) {
            return _failure(FailureCode.EMPTY_PLAN, type(uint256).max, 0, 0, 0);
        }

        return _evaluateValidPlan(plan, effectiveRules, mandate.vault, registryContract);
    }

    function decodeSwapParameters(bytes calldata data)
        external
        pure
        returns (ActionTypes.SwapParameters memory params)
    {
        return abi.decode(data, (ActionTypes.SwapParameters));
    }

    function _evaluateValidPlan(
        ActionTypes.ActionPlan calldata plan,
        GrantlineTypes.MandateRules memory effectiveRules,
        address vault,
        IRegistry registryContract
    ) private view returns (GrantlineTypes.EvaluationResult memory) {
        (bool valid, Totals memory totals, FailureCode validationFailure, uint256 failedActionIndex) =
            _validatePlan(plan, vault);
        if (!valid) {
            return _failure(validationFailure, failedActionIndex, totals.nativeAmount, 0, 0);
        }

        bool nativeUsdRuleEnabled = effectiveRules.minNativeUsd != 0 || effectiveRules.maxNativeUsd != 0;
        if (nativeUsdRuleEnabled && totals.nativeEquivalentAmount != 0) {
            (bool available, uint256 nativeUsdValue, uint256 nativeUsdValueCeiling) =
                _quoteNativeUsd(totals.nativeEquivalentAmount);
            if (!available) {
                return
                    _failure(FailureCode.NATIVE_USD_VALUATION_UNAVAILABLE, type(uint256).max, totals.nativeAmount, 0, 0);
            }
            totals.nativeUsdValue = nativeUsdValue;
            totals.nativeUsdValueCeiling = nativeUsdValueCeiling;
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
        uint256 nativeEquivalentAmount;
        uint256 nativeUsdValue;
        uint256 nativeUsdValueCeiling;
    }

    struct RuleViolations {
        bool nativeMinimum;
        bool nativeMaximum;
        bool nativeUsdMinimum;
        bool nativeUsdMaximum;
        bool preflightNativeBalance;
    }

    function _validatePlan(ActionTypes.ActionPlan calldata plan, address vault)
        private
        view
        returns (bool, Totals memory totals, FailureCode, uint256)
    {
        uint256 failedActionIndex = type(uint256).max;
        for (uint256 index; index < plan.actions.length; index++) {
            (bool actionValid, Totals memory updatedTotals, FailureCode actionFailure) =
                _validateAction(plan.actions[index], totals, vault);
            totals = updatedTotals;
            if (!actionValid) return (false, totals, actionFailure, index);
        }
        return (true, totals, FailureCode.NONE, failedActionIndex);
    }

    function _validateAction(ActionTypes.Action calldata action, Totals memory currentTotals, address vault)
        private
        view
        returns (bool, Totals memory totals, FailureCode)
    {
        totals = currentTotals;
        if (action.parameters.length == 0) return (false, totals, FailureCode.INVALID_ACTION);

        if (action.actionType == ActionTypes.ActionType.TRANSFER) {
            if (action.version != ActionTypes.TRANSFER_VERSION) {
                return (false, totals, FailureCode.INVALID_ACTION);
            }
            if (action.parameters.length != 96) {
                return (false, totals, FailureCode.INVALID_ACTION_PARAMETERS);
            }

            ActionTypes.TransferParameters memory transfer =
                abi.decode(action.parameters, (ActionTypes.TransferParameters));
            if (transfer.recipient == address(0)) {
                return (false, totals, FailureCode.INVALID_RECIPIENT);
            }
            if (transfer.amount == 0) {
                return (false, totals, FailureCode.INVALID_AMOUNT);
            }
            return _accumulate(totals, transfer.asset, transfer.amount);
        }

        if (action.actionType != ActionTypes.ActionType.SWAP || action.version != ActionTypes.SWAP_VERSION) {
            return (false, totals, FailureCode.INVALID_ACTION);
        }

        try this.decodeSwapParameters(action.parameters) returns (ActionTypes.SwapParameters memory swap) {
            if (swap.amountIn == 0 || swap.minAmountOut == 0 || swap.deadline == 0 || swap.hops.length == 0) {
                return (false, totals, FailureCode.INVALID_SWAP_PARAMETERS);
            }
            if (block.timestamp > swap.deadline) return (false, totals, FailureCode.SWAP_DEADLINE_EXPIRED);

            address swapAdapter = IGrantlineContext(grantline).swapAdapterFor(swap.swapAdapterId);
            if (swapAdapter == address(0)) return (false, totals, FailureCode.SWAP_UNSUPPORTED);
            try ISwapAdapter(swapAdapter).validateSwap(swap, vault) returns (bool valid) {
                if (!valid) return (false, totals, FailureCode.INVALID_SWAP_ROUTE);
            } catch {
                return (false, totals, FailureCode.INVALID_SWAP_ROUTE);
            }
            return _accumulate(totals, swap.tokenIn, swap.amountIn);
        } catch {
            return (false, totals, FailureCode.INVALID_SWAP_PARAMETERS);
        }
    }

    function _accumulate(Totals memory totals, address asset, uint256 amount)
        private
        view
        returns (bool, Totals memory, FailureCode)
    {
        if (asset == address(0)) {
            if (totals.nativeAmount > type(uint256).max - amount) {
                return (false, totals, FailureCode.AMOUNT_OVERFLOW);
            }
            totals.nativeAmount += amount;
        }
        if (asset == address(0) || (wrappedNative != address(0) && asset == wrappedNative)) {
            if (totals.nativeEquivalentAmount > type(uint256).max - amount) {
                return (false, totals, FailureCode.AMOUNT_OVERFLOW);
            }
            totals.nativeEquivalentAmount += amount;
        }
        return (true, totals, FailureCode.NONE);
    }

    function _applyRules(
        GrantlineTypes.MandateRules memory rules,
        GrantlineTypes.PreflightRules memory preflightRules,
        Totals memory totals,
        uint256 nativeBalanceAfter
    ) private view returns (GrantlineTypes.EvaluationResult memory) {
        RuleViolations memory violations = _findRuleViolations(rules, preflightRules, totals, nativeBalanceAfter);
        bool nativeViolation = violations.nativeMinimum || violations.nativeMaximum;
        bool nativeUsdViolation = violations.nativeUsdMinimum || violations.nativeUsdMaximum;
        FailureCode nativeFailureCode = violations.nativeMinimum
            ? FailureCode.NATIVE_AMOUNT_BELOW_MINIMUM
            : FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM;
        FailureCode nativeUsdFailureCode = violations.nativeUsdMinimum
            ? FailureCode.NATIVE_USD_VALUE_BELOW_MINIMUM
            : FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM;

        if (nativeViolation && !rules.escalateNativeAmount) {
            return _decision(Decision.DENY, nativeFailureCode, totals, nativeBalanceAfter);
        }
        if (nativeUsdViolation && !rules.escalateNativeUsd) {
            return _decision(Decision.DENY, nativeUsdFailureCode, totals, nativeBalanceAfter);
        }
        if (violations.preflightNativeBalance && !preflightRules.escalateNativeBalance) {
            return
                _decision(Decision.DENY, FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM, totals, nativeBalanceAfter);
        }
        if (nativeViolation || nativeUsdViolation || violations.preflightNativeBalance) {
            return _decision(
                Decision.ESCALATE,
                nativeViolation
                    ? nativeFailureCode
                    : nativeUsdViolation ? nativeUsdFailureCode : FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM,
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
    ) private view returns (RuleViolations memory violations) {
        violations.nativeMinimum = totals.nativeAmount != 0 && rules.minNativeAmount != 0
            && totals.nativeAmount < rules.minNativeAmount;
        violations.nativeMaximum = rules.maxNativeAmount != 0 && totals.nativeAmount > rules.maxNativeAmount;
        if (totals.nativeEquivalentAmount != 0) {
            uint256 scale = 10 ** uint256(chainlinkNativeUsdFeedDecimals);
            violations.nativeUsdMinimum = rules.minNativeUsd != 0 && totals.nativeUsdValue < rules.minNativeUsd * scale;
            violations.nativeUsdMaximum =
                rules.maxNativeUsd != 0 && totals.nativeUsdValueCeiling > rules.maxNativeUsd * scale;
        }
        violations.preflightNativeBalance =
            preflightRules.minNativeBalance != 0 && nativeBalanceAfter < preflightRules.minNativeBalance;
    }

    function _failure(
        FailureCode failureCode,
        uint256 actionIndex,
        uint256 nativeAmount,
        uint256 nativeUsdValue,
        uint256 nativeBalanceAfter
    ) private pure returns (GrantlineTypes.EvaluationResult memory) {
        return GrantlineTypes.EvaluationResult({
            decision: uint8(Decision.DENY),
            failureCode: uint8(failureCode),
            failedActionIndex: actionIndex,
            nativeAmount: nativeAmount,
            nativeUsdValue: nativeUsdValue,
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
            nativeUsdValue: totals.nativeUsdValue,
            nativeBalanceAfter: nativeBalanceAfter
        });
    }

    function _quoteNativeUsd(uint256 nativeEquivalentAmount)
        private
        view
        returns (bool available, uint256 value, uint256 valueCeiling)
    {
        address feed = chainlinkNativeUsdFeed;
        if (feed == address(0)) return (false, 0, 0);

        try IChainlinkAggregatorV3(feed).decimals() returns (uint8 actualDecimals) {
            if (actualDecimals != chainlinkNativeUsdFeedDecimals) return (false, 0, 0);
        } catch {
            return (false, 0, 0);
        }

        try IChainlinkAggregatorV3(feed).latestRoundData() returns (uint80, int256 answer, uint256, uint256, uint80) {
            if (answer <= 0) return (false, 0, 0);
            uint256 unsignedAnswer = SafeCast.toUint256(answer);
            return _tryNativeUsdQuote(nativeEquivalentAmount, unsignedAnswer);
        } catch {
            return (false, 0, 0);
        }
    }

    function _tryNativeUsdQuote(uint256 nativeEquivalentAmount, uint256 answer)
        private
        pure
        returns (bool available, uint256 value, uint256 valueCeiling)
    {
        (uint256 productHigh, uint256 productLow) = Math.mul512(nativeEquivalentAmount, answer);
        if (productHigh >= 1 ether) return (false, 0, 0);

        uint256 remainder;
        if (productHigh == 0) {
            value = productLow / 1 ether;
            remainder = productLow % 1 ether;
        } else {
            value = Math.mulDiv(nativeEquivalentAmount, answer, 1 ether);
            remainder = mulmod(nativeEquivalentAmount, answer, 1 ether);
        }
        if (remainder == 0) return (true, value, value);
        if (value == type(uint256).max) return (false, 0, 0);
        return (true, value, value + 1);
    }

    function _validateNativeUsdConfiguration(address feed, uint8 feedDecimals, address wrappedNativeAddress)
        private
        view
    {
        if (feed == address(0)) {
            if (feedDecimals != 0) revert InvalidNativeUsdConfiguration();
        } else {
            if (
                feed.code.length == 0 || feedDecimals > MAX_CHAINLINK_FEED_DECIMALS
                    || wrappedNativeAddress == address(0)
            ) revert InvalidNativeUsdConfiguration();
            try IChainlinkAggregatorV3(feed).decimals() returns (uint8 actualDecimals) {
                if (actualDecimals != feedDecimals) revert InvalidNativeUsdConfiguration();
            } catch {
                revert InvalidNativeUsdConfiguration();
            }
        }

        if (wrappedNativeAddress != address(0)) {
            if (wrappedNativeAddress.code.length == 0) revert InvalidNativeUsdConfiguration();
            try IERC20Metadata(wrappedNativeAddress).decimals() returns (uint8 actualDecimals) {
                if (actualDecimals != 18) revert InvalidNativeUsdConfiguration();
            } catch {
                revert InvalidNativeUsdConfiguration();
            }
        }
    }

    function _onlyTrustedCaller() private view {
        if (
            msg.sender != grantline && msg.sender != IGrantlineContext(grantline).moduleAddress(EXECUTOR_MODULE)
                && msg.sender != IGrantlineContext(grantline).moduleAddress(ESCALATION_MANAGER_MODULE)
        ) revert NotTrustedCaller(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
