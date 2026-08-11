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
        TRANSACTION_LIMIT_EXCEEDED,
        USD_AMOUNT_OVERFLOW,
        USD_LIMIT_EXCEEDED,
        USD_VALUATION_UNAVAILABLE
    }

    struct EvaluationResult {
        bool passed;
        FailureCode failureCode;
        uint256 failedActionIndex;
        uint256 nativeAmount;
        uint256 usdAmount;
        bool usdLimitSkipped;
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
                    false
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
                    false
                );
        }
        if (plan.agent != mandate.agent) {
            return
                _failure(
                    FailureCode.AGENT_MISMATCH,
                    type(uint256).max,
                    0,
                    0,
                    false
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
                    false
                );
        }
        if (plan.deadline != 0 && block.timestamp > plan.deadline) {
            return
                _failure(FailureCode.EXPIRED, type(uint256).max, 0, 0, false);
        }
        if (plan.actions.length == 0) {
            return
                _failure(
                    FailureCode.EMPTY_PLAN,
                    type(uint256).max,
                    0,
                    0,
                    false
                );
        }

        uint256 nativeAmount;
        uint256 usdAmount;
        bool usdLimitSkipped;
        for (uint256 index; index < plan.actions.length; index++) {
            (
                bool valid,
                uint256 updatedNativeAmount,
                uint256 updatedUsdAmount,
                bool updatedUsdLimitSkipped,
                FailureCode failureCode
            ) = _validateAction(
                    plan.actions[index],
                    nativeAmount,
                    usdAmount,
                    usdLimitSkipped,
                    mandate.transactionLimit,
                    mandate.usdTransactionLimit
                );
            if (!valid) {
                return
                    _failure(
                        failureCode,
                        index,
                        updatedNativeAmount,
                        updatedUsdAmount,
                        updatedUsdLimitSkipped
                    );
            }
            nativeAmount = updatedNativeAmount;
            usdAmount = updatedUsdAmount;
            usdLimitSkipped = updatedUsdLimitSkipped;
        }

        return
            EvaluationResult({
                passed: true,
                failureCode: FailureCode.NONE,
                failedActionIndex: type(uint256).max,
                nativeAmount: nativeAmount,
                usdAmount: usdAmount,
                usdLimitSkipped: usdLimitSkipped
            });
    }

    function _validateAction(
        ActionTypes.Action calldata action,
        uint256 currentNativeAmount,
        uint256 currentUsdAmount,
        bool currentUsdLimitSkipped,
        uint256 transactionLimit,
        uint256 usdTransactionLimit
    )
        private
        view
        returns (
            bool valid,
            uint256 nativeAmount,
            uint256 usdAmount,
            bool usdLimitSkipped,
            FailureCode failureCode
        )
    {
        if (action.version == 0 || action.parameters.length == 0) {
            return (
                false,
                currentNativeAmount,
                currentUsdAmount,
                currentUsdLimitSkipped,
                FailureCode.INVALID_ACTION
            );
        }

        nativeAmount = currentNativeAmount;
        usdAmount = currentUsdAmount;
        usdLimitSkipped = currentUsdLimitSkipped;
        if (action.actionType == ActionTypes.ActionType.TRANSFER) {
            if (action.parameters.length != 96) {
                return (
                    false,
                    nativeAmount,
                    usdAmount,
                    usdLimitSkipped,
                    FailureCode.INVALID_ACTION_PARAMETERS
                );
            }

            ActionTypes.TransferParameters memory transfer = abi.decode(
                action.parameters,
                (ActionTypes.TransferParameters)
            );
            if (transfer.recipient == address(0)) {
                return (
                    false,
                    nativeAmount,
                    usdAmount,
                    usdLimitSkipped,
                    FailureCode.INVALID_RECIPIENT
                );
            }
            if (transfer.amount == 0) {
                return (
                    false,
                    nativeAmount,
                    usdAmount,
                    usdLimitSkipped,
                    FailureCode.INVALID_AMOUNT
                );
            }

            if (transfer.asset == address(0)) {
                if (nativeAmount > type(uint256).max - transfer.amount) {
                    return (
                        false,
                        nativeAmount,
                        usdAmount,
                        usdLimitSkipped,
                        FailureCode.AMOUNT_OVERFLOW
                    );
                }
                nativeAmount += transfer.amount;
                if (transactionLimit != 0 && nativeAmount > transactionLimit) {
                    return (
                        false,
                        nativeAmount,
                        usdAmount,
                        usdLimitSkipped,
                        FailureCode.TRANSACTION_LIMIT_EXCEEDED
                    );
                }
            }

            if (usdTransactionLimit != 0 && !usdLimitSkipped) {
                (uint256 actionUsdAmount, bool available) = _quoteUsd(
                    transfer.asset,
                    transfer.amount
                );
                if (!available) {
                    if (!skipUnavailableUsdValuation) {
                        return (
                            false,
                            nativeAmount,
                            usdAmount,
                            usdLimitSkipped,
                            FailureCode.USD_VALUATION_UNAVAILABLE
                        );
                    }
                    usdLimitSkipped = true;
                    usdAmount = 0;
                } else {
                    if (usdAmount > type(uint256).max - actionUsdAmount) {
                        return (
                            false,
                            nativeAmount,
                            usdAmount,
                            usdLimitSkipped,
                            FailureCode.USD_AMOUNT_OVERFLOW
                        );
                    }
                    usdAmount += actionUsdAmount;
                    if (usdAmount > usdTransactionLimit) {
                        return (
                            false,
                            nativeAmount,
                            usdAmount,
                            usdLimitSkipped,
                            FailureCode.USD_LIMIT_EXCEEDED
                        );
                    }
                }
            }
        }

        return (
            true,
            nativeAmount,
            usdAmount,
            usdLimitSkipped,
            FailureCode.NONE
        );
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
        bool usdLimitSkipped
    ) private pure returns (EvaluationResult memory) {
        return
            EvaluationResult({
                passed: false,
                failureCode: failureCode,
                failedActionIndex: actionIndex,
                nativeAmount: nativeAmount,
                usdAmount: usdAmount,
                usdLimitSkipped: usdLimitSkipped
            });
    }
}
