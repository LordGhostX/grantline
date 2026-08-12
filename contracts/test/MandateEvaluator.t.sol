// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {IUsdValueProvider, MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";

interface EvaluatorVm {
    function addr(uint256 privateKey) external returns (address);

    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external returns (uint8 v, bytes32 r, bytes32 s);

    function warp(uint256 timestamp) external;

    function prank(address sender) external;
}

contract MockUsdValueProvider is IUsdValueProvider {
    mapping(address asset => uint256 usdQuote) private _quotes;
    mapping(address asset => bool available) private _available;

    function setQuote(address asset, uint256 usdQuote) external {
        _quotes[asset] = usdQuote;
        _available[asset] = true;
    }

    function setUnavailable(address asset) external {
        _available[asset] = false;
    }

    function quoteUsd(
        address asset,
        uint256
    ) external view returns (uint256 usdAmount, bool available) {
        return (_quotes[asset], _available[asset]);
    }
}

contract MandateEvaluatorTest {
    EvaluatorVm private constant vm =
        EvaluatorVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_evaluatesSignedNativePlanUnderAggregateLimit() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 3 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 4 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.failureCode == MandateEvaluator.FailureCode.NONE);
        assert(result.failedActionIndex == type(uint256).max);
        assert(result.nativeAmount == 7 ether);
    }

    function test_childEvaluationUsesInheritedRulesAndRevocation() public {
        uint256 parentKey = 0xA11CE;
        uint256 childKey = 0xB0B;
        address parentAgent = vm.addr(parentKey);
        address childAgent = vm.addr(childKey);
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 parentId = registry.createMandate(
            address(vault),
            parentAgent,
            _delegatableRules(10 ether)
        );

        vm.prank(parentAgent);
        uint256 childId = registry.createChildMandate(
            parentId,
            childAgent,
            _rules(5 ether, 0)
        );
        MandateEvaluator evaluator = new MandateEvaluator(
            address(registry),
            address(0),
            true
        );
        ActionTypes.ActionPlan memory plan = _plan(
            childId,
            childAgent,
            6 ether,
            0
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, childKey)
        );
        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM
        );

        registry.revokeMandate(parentId);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        result = evaluator.evaluate(plan, _sign(evaluator, plan, childKey));
        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode == MandateEvaluator.FailureCode.MANDATE_INACTIVE
        );
    }

    function test_rejectsPlanWhenAggregateNativeAmountExceedsLimit() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 6 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 5 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM
        );
        assert(result.failedActionIndex == type(uint256).max);
        assert(result.nativeAmount == 11 ether);
    }

    function test_evaluatesAggregateUsdTransferLimit() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        address token = address(0xCAFE);
        provider.setQuote(address(0), 2_000e18);
        provider.setQuote(token, 500e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(10 ether, 2_500e18, address(provider), false);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        plan.actions[1] = _transferAction(token, address(0xD00D), 1);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.usdAmount == 2_500e18);
        assert(!result.usdLimitSkipped);
    }

    function test_rejectsPlanWhenAggregateUsdAmountExceedsLimit() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        provider.setQuote(address(0), 2_000e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(10 ether, 3_000e18, address(provider), false);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 1 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM
        );
        assert(result.failedActionIndex == type(uint256).max);
        assert(result.usdAmount == 4_000e18);
    }

    function test_nativeAndUsdLimitsApplyIndependently() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        provider.setQuote(address(0), 2_000e18);

        (
            MandateEvaluator nativeLimitedEvaluator,
            ActionTypes.ActionPlan memory nativeLimitedPlan,
            uint256 nativePrivateKey
        ) = _setupWithUsd(1 ether, 5_000e18, address(provider), false);
        nativeLimitedPlan.actions[0] = _transferAction(
            address(0),
            address(0xBEEF),
            2 ether
        );
        MandateEvaluator.EvaluationResult
            memory nativeResult = nativeLimitedEvaluator.evaluate(
                nativeLimitedPlan,
                _sign(
                    nativeLimitedEvaluator,
                    nativeLimitedPlan,
                    nativePrivateKey
                )
            );

        assert(nativeResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            nativeResult.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM
        );

        (
            MandateEvaluator usdLimitedEvaluator,
            ActionTypes.ActionPlan memory usdLimitedPlan,
            uint256 usdPrivateKey
        ) = _setupWithUsd(10 ether, 1_000e18, address(provider), false);
        MandateEvaluator.EvaluationResult memory usdResult = usdLimitedEvaluator
            .evaluate(
                usdLimitedPlan,
                _sign(usdLimitedEvaluator, usdLimitedPlan, usdPrivateKey)
            );

        assert(usdResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            usdResult.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM
        );
    }

    function test_skipsUnavailableUsdValuationWhenConfigured() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(0, 1_000e18, address(provider), true);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.usdAmount == 0);
        assert(result.usdLimitSkipped);
    }

    function test_enforcesAvailableUsdSubtotalRegardlessOfActionOrder() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        address unavailableToken = address(0xCAFE);
        address quotedToken = address(0xF00D);
        provider.setQuote(quotedToken, 1_200e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(0, 1_000e18, address(provider), true);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(unavailableToken, address(0xBEEF), 1);
        plan.actions[1] = _transferAction(quotedToken, address(0xD00D), 1);

        MandateEvaluator.EvaluationResult memory unavailableFirst = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));

        plan.actions[0] = _transferAction(quotedToken, address(0xD00D), 1);
        plan.actions[1] = _transferAction(unavailableToken, address(0xBEEF), 1);
        MandateEvaluator.EvaluationResult memory quotedFirst = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));

        assert(unavailableFirst.decision == MandateEvaluator.Decision.DENY);
        assert(quotedFirst.decision == MandateEvaluator.Decision.DENY);
        assert(
            unavailableFirst.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM
        );
        assert(
            quotedFirst.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM
        );
        assert(unavailableFirst.usdAmount == 1_200e18);
        assert(quotedFirst.usdAmount == 1_200e18);
    }

    function test_preservesAvailableUsdSubtotalWhenValuationIsSkipped() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        address unavailableToken = address(0xCAFE);
        address quotedToken = address(0xF00D);
        provider.setQuote(quotedToken, 600e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(0, 1_000e18, address(provider), true);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(unavailableToken, address(0xBEEF), 1);
        plan.actions[1] = _transferAction(quotedToken, address(0xD00D), 1);

        MandateEvaluator.EvaluationResult memory unavailableFirst = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));

        plan.actions[0] = _transferAction(quotedToken, address(0xD00D), 1);
        plan.actions[1] = _transferAction(unavailableToken, address(0xBEEF), 1);
        MandateEvaluator.EvaluationResult memory quotedFirst = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));

        assert(unavailableFirst.decision == MandateEvaluator.Decision.ALLOW);
        assert(quotedFirst.decision == MandateEvaluator.Decision.ALLOW);
        assert(unavailableFirst.usdAmount == 600e18);
        assert(quotedFirst.usdAmount == 600e18);
        assert(unavailableFirst.usdLimitSkipped);
        assert(quotedFirst.usdLimitSkipped);
    }

    function test_aggregatesQuotesAroundUnavailableValuation() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        address firstQuotedToken = address(0xCAFE);
        address unavailableToken = address(0xBAD);
        address secondQuotedToken = address(0xF00D);
        provider.setQuote(firstQuotedToken, 600e18);
        provider.setQuote(secondQuotedToken, 500e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(0, 1_000e18, address(provider), true);
        plan.actions = new ActionTypes.Action[](3);
        plan.actions[0] = _transferAction(firstQuotedToken, address(0xBEEF), 1);
        plan.actions[1] = _transferAction(unavailableToken, address(0xD00D), 1);
        plan.actions[2] = _transferAction(
            secondQuotedToken,
            address(0xC0DE),
            1
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM
        );
        assert(result.failedActionIndex == type(uint256).max);
        assert(result.usdAmount == 1_100e18);
        assert(result.usdLimitSkipped);
    }

    function test_rejectsUsdOverflowAfterUnavailableValuation() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        address firstQuotedToken = address(0xCAFE);
        address unavailableToken = address(0xBAD);
        address secondQuotedToken = address(0xF00D);
        provider.setQuote(firstQuotedToken, type(uint256).max);
        provider.setQuote(secondQuotedToken, 1);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(0, type(uint256).max, address(provider), true);
        plan.actions = new ActionTypes.Action[](3);
        plan.actions[0] = _transferAction(unavailableToken, address(0xBEEF), 1);
        plan.actions[1] = _transferAction(firstQuotedToken, address(0xD00D), 1);
        plan.actions[2] = _transferAction(
            secondQuotedToken,
            address(0xC0DE),
            1
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_OVERFLOW
        );
        assert(result.failedActionIndex == 2);
        assert(result.usdAmount == type(uint256).max);
        assert(result.usdLimitSkipped);
    }

    function test_skippingUsdValuationStillEnforcesNativeLimit() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(1 ether, 1_000e18, address(provider), true);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM
        );
        assert(result.usdLimitSkipped);
    }

    function test_rejectsUnavailableUsdValuationWhenNotSkipped() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(0, 1_000e18, address(provider), false);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_VALUATION_UNAVAILABLE
        );
    }

    function test_rejectsUsdAmountOverflow() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        provider.setQuote(address(0), type(uint256).max);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(
                10 ether,
                type(uint256).max,
                address(provider),
                false
            );
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 1 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_OVERFLOW
        );
        assert(result.failedActionIndex == 1);
    }

    function test_disabledLimitAllowsTokenTransfer() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        plan.actions[0] = _transferAction(
            address(0xCAFE),
            address(0xBEEF),
            1_000_000 ether
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.nativeAmount == 0);
    }

    function test_enabledLimitDoesNotRejectTokenTransferWithoutAssetGuard()
        public
    {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0] = _transferAction(
            address(0xCAFE),
            address(0xBEEF),
            1_000_000 ether
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.nativeAmount == 0);
    }

    function test_rejectsUnsupportedTransferVersions() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0].version = 2;

        MandateEvaluator.EvaluationResult memory versionTwoResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(versionTwoResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            versionTwoResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_ACTION
        );
        assert(versionTwoResult.failedActionIndex == 0);
        assert(versionTwoResult.nativeAmount == 0);

        plan.actions[0].version = type(uint8).max;
        MandateEvaluator.EvaluationResult memory maxVersionResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(maxVersionResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            maxVersionResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_ACTION
        );
        assert(maxVersionResult.failedActionIndex == 0);
        assert(maxVersionResult.nativeAmount == 0);
    }

    function test_rejectsZeroTransferVersion() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0].version = 0;

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode == MandateEvaluator.FailureCode.INVALID_ACTION
        );
        assert(result.failedActionIndex == 0);
    }

    function test_rejectsMandateAgentSignatureAndDeadlineFailures() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.agent = address(0xCAFE);

        MandateEvaluator.EvaluationResult memory agentResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(agentResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            agentResult.failureCode ==
                MandateEvaluator.FailureCode.AGENT_MISMATCH
        );

        plan.agent = vm.addr(privateKey);
        plan.deadline = 1;
        vm.warp(2);
        MandateEvaluator.EvaluationResult memory deadlineResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(deadlineResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            deadlineResult.failureCode == MandateEvaluator.FailureCode.EXPIRED
        );
    }

    function test_rejectsInvalidActionShape() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0] = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: 0,
            parameters: hex"01"
        });

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode == MandateEvaluator.FailureCode.INVALID_ACTION
        );
        assert(result.failedActionIndex == 0);
    }

    function test_rejectsInvalidTransferParameters() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0].parameters = hex"01";

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.INVALID_ACTION_PARAMETERS
        );
        assert(result.failedActionIndex == 0);
    }

    function test_rejectsEmptyPlan() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions = new ActionTypes.Action[](0);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(result.failureCode == MandateEvaluator.FailureCode.EMPTY_PLAN);
    }

    function test_rejectsInvalidSignatureRecipientAndAmount() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        MandateEvaluator.EvaluationResult memory signatureResult = evaluator
            .evaluate(plan, hex"");

        assert(signatureResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            signatureResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_SIGNATURE
        );

        plan.actions[0] = _transferAction(address(0), address(0), 1 ether);
        MandateEvaluator.EvaluationResult memory recipientResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(recipientResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            recipientResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_RECIPIENT
        );

        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 0);
        MandateEvaluator.EvaluationResult memory amountResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(amountResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            amountResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_AMOUNT
        );
    }

    function test_rejectsUnknownAndRevokedMandates() public {
        MandateRegistry registry = new MandateRegistry();
        MandateEvaluator evaluator = new MandateEvaluator(
            address(registry),
            address(0),
            true
        );
        ActionTypes.ActionPlan memory unknownPlan = _plan(
            1,
            address(0xA11CE),
            1 ether,
            0
        );

        MandateEvaluator.EvaluationResult memory unknownResult = evaluator
            .evaluate(unknownPlan, hex"");
        assert(unknownResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            unknownResult.failureCode ==
                MandateEvaluator.FailureCode.MANDATE_NOT_FOUND
        );

        Vault vault = new Vault();
        uint256 mandateId = registry.createMandate(
            address(vault),
            address(0xA11CE),
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: 10 ether,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false,
                canDelegate: false
            })
        );
        registry.revokeMandate(mandateId);
        ActionTypes.ActionPlan memory revokedPlan = _plan(
            mandateId,
            address(0xA11CE),
            1 ether,
            0
        );

        MandateEvaluator.EvaluationResult memory revokedResult = evaluator
            .evaluate(revokedPlan, hex"");
        assert(revokedResult.decision == MandateEvaluator.Decision.DENY);
        assert(
            revokedResult.failureCode ==
                MandateEvaluator.FailureCode.MANDATE_INACTIVE
        );
    }

    function test_escalatesConfiguredNativeLimitOverrun() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: 1 ether,
                    escalateNativeAmount: true,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(0),
                true
            );
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ESCALATE);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM
        );
        assert(result.nativeAmount == 2 ether);
    }

    function test_hardLimitOverrunCannotBeEscalatedThroughOtherFlag() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        provider.setQuote(address(0), 2_000e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: 1 ether,
                    escalateNativeAmount: true,
                    minUsdAmount: 0,
                    maxUsdAmount: 1_000e18,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(provider),
                false
            );
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM
        );
    }

    function test_rejectsNativeAmountBelowMinimum() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 2 ether,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(0),
                true
            );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_BELOW_MINIMUM
        );
        assert(result.nativeAmount == 1 ether);
    }

    function test_nativeMinimumUsesAggregatePlanAmount() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 7 ether,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(0),
                true
            );
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 3 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 4 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.nativeAmount == 7 ether);
    }

    function test_escalatesConfiguredNativeMinimum() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 2 ether,
                    maxNativeAmount: 0,
                    escalateNativeAmount: true,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(0),
                true
            );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ESCALATE);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.NATIVE_AMOUNT_BELOW_MINIMUM
        );
    }

    function test_skipsNativeMinimumForTokenOnlyPlan() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 2 ether,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(0),
                true
            );
        plan.actions[0] = _transferAction(address(0xCAFE), address(0xBEEF), 1);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.nativeAmount == 0);
    }

    function test_rejectsUsdAmountBelowMinimum() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        provider.setQuote(address(0), 500e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 1_000e18,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(provider),
                false
            );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_BELOW_MINIMUM
        );
        assert(result.usdAmount == 500e18);
    }

    function test_usdMinimumUsesAggregateQuotedAmount() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        address firstToken = address(0xCAFE);
        address secondToken = address(0xF00D);
        provider.setQuote(firstToken, 400e18);
        provider.setQuote(secondToken, 600e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 1_000e18,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(provider),
                false
            );
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(firstToken, address(0xBEEF), 1);
        plan.actions[1] = _transferAction(secondToken, address(0xD00D), 1);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.usdAmount == 1_000e18);
    }

    function test_skipsUsdMinimumWhenValuationUnavailable() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 1_000e18,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(provider),
                true
            );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.ALLOW);
        assert(result.usdAmount == 0);
        assert(result.usdLimitSkipped);
    }

    function test_exactAggregateBoundsAreAllowed() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 1 ether,
                    maxNativeAmount: 2 ether,
                    escalateNativeAmount: false,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(0),
                true
            );

        MandateEvaluator.EvaluationResult memory minimumResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2 ether);
        MandateEvaluator.EvaluationResult memory maximumResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));

        assert(minimumResult.decision == MandateEvaluator.Decision.ALLOW);
        assert(maximumResult.decision == MandateEvaluator.Decision.ALLOW);
    }

    function test_hardMinimumCannotBeEscalatedThroughOtherFlag() public {
        MockUsdValueProvider provider = new MockUsdValueProvider();
        provider.setQuote(address(0), 500e18);
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 2 ether,
                    maxNativeAmount: 0,
                    escalateNativeAmount: true,
                    minUsdAmount: 1_000e18,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                address(provider),
                false
            );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.decision == MandateEvaluator.Decision.DENY);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.USD_AMOUNT_BELOW_MINIMUM
        );
    }

    function _setup(
        uint256 maxNativeAmount
    )
        private
        returns (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        return _setupWithUsd(maxNativeAmount, 0, address(0), true);
    }

    function _delegatableRules(
        uint256 maxNativeAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false,
                canDelegate: true
            });
    }

    function _rules(
        uint256 maxNativeAmount,
        uint256 maxUsdAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                canDelegate: false,
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: maxUsdAmount,
                escalateUsdAmount: false
            });
    }

    function _setupWithUsd(
        uint256 maxNativeAmount,
        uint256 maxUsdAmount,
        address usdValueProvider,
        bool skipUnavailableUsdValuation
    )
        private
        returns (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        return
            _setupWithRules(
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: maxNativeAmount,
                    escalateNativeAmount: false,
                    minUsdAmount: 0,
                    maxUsdAmount: maxUsdAmount,
                    escalateUsdAmount: false,
                    canDelegate: false
                }),
                usdValueProvider,
                skipUnavailableUsdValuation
            );
    }

    function _setupWithRules(
        MandateRegistry.MandateRules memory rules,
        address usdValueProvider,
        bool skipUnavailableUsdValuation
    )
        private
        returns (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            rules
        );
        evaluator = new MandateEvaluator(
            address(registry),
            usdValueProvider,
            skipUnavailableUsdValuation
        );
        plan = _plan(mandateId, agent, 1 ether, 0);
    }

    function _plan(
        uint256 mandateId,
        address agent,
        uint256 amount,
        uint256 deadline
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = _transferAction(address(0), address(0xBEEF), amount);
        return
            ActionTypes.ActionPlan({
                mandateId: mandateId,
                agent: agent,
                nonce: 1,
                deadline: deadline,
                actions: actions
            });
    }

    function _transferAction(
        address asset,
        address recipient,
        uint256 amount
    ) private pure returns (ActionTypes.Action memory) {
        return
            ActionTypes.Action({
                actionType: ActionTypes.ActionType.TRANSFER,
                version: 1,
                parameters: abi.encode(
                    ActionTypes.TransferParameters({
                        asset: asset,
                        recipient: recipient,
                        amount: amount
                    })
                )
            });
    }

    function _sign(
        MandateEvaluator evaluator,
        ActionTypes.ActionPlan memory plan,
        uint256 privateKey
    ) private returns (bytes memory signature) {
        bytes32 digest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
