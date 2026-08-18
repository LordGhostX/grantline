// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {IEvaluator} from "../src/Interfaces.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {NativeUsdFeedMock, NativeUsdTokenMock} from "./NativeUsdMocks.sol";
import {TestFixture} from "./TestFixture.sol";

contract NativeUsdEvaluatorV2 is MandateEvaluator {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract NativeUsdTest is TestFixture {
    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant FIFTY_USD = 50e8;
    address private constant RECIPIENT = address(0xD00D);

    function test_wholeDollarMaximumUsesManifestFeedDecimals() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 4 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeAmount == 4 ether);
        assert(result.nativeUsdValue == 200e8);

        rules.maxNativeUsd = 199;
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 0, false), 0, 0);
        result = _evaluateNative(fixture, 4 ether, 2);
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM));
    }

    function test_wholeDollarMinimumIsInclusiveAndRoundsConservatively() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(200, 0, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 4 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));

        result = _evaluateNative(fixture, 4 ether - 1, 2);
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_BELOW_MINIMUM));
    }

    function test_fractionAboveWholeDollarMaximumCannotRoundDownIntoAllowance() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 4 ether + 1, 1);
        assert(result.nativeUsdValue == 200e8);
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM));
    }

    function test_feedDecimalsAreConfigurationDriven() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(6, 50e6, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 4 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeUsdValue == 200e6);

        (bool enabled,, uint8 decimals,) = fixture.hub.getNativeUsdValuation();
        assert(enabled);
        assert(decimals == 6);
    }

    function test_eighteenDecimalFeedSupportsAnswersAboveOneEther() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(18, 50e18, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 4 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeUsdValue == 200e18);
    }

    function test_nativeUsdFloorOverflowFailsClosedWithoutReverting() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 1, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(18, 50e18, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, type(uint256).max, 1);
        _assertValuationUnavailable(result);
        assert(result.nativeAmount == type(uint256).max);
        assert(result.nativeUsdValue == 0);
    }

    function test_nativeUsdCeilingOverflowFailsClosedWithoutReverting() public {
        uint256 answer = 1 ether + 1;
        uint256 amount = Math.mulDiv(type(uint256).max, 1 ether, answer) + 1;
        assert(Math.mulDiv(amount, answer, 1 ether) == type(uint256).max);
        assert(mulmod(amount, answer, 1 ether) != 0);

        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 1, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(18, 1e18 + 1, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, amount, 1);
        _assertValuationUnavailable(result);
        assert(result.nativeAmount == amount);
        assert(result.nativeUsdValue == 0);
    }

    function test_wrappedNativeTransferCountsWithoutChangingNativeAmount() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 199, false);
        (Fixture memory fixture,, NativeUsdTokenMock wrappedNative) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        wrappedNative.mint(fixture.vault, 4 ether);

        GrantlineTypes.EvaluationResult memory result = _evaluateToken(fixture, address(wrappedNative), 4 ether, 1);
        assert(result.nativeAmount == 0);
        assert(result.nativeUsdValue == 200e8);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM));
    }

    function test_nativeAndWrappedInputsAggregateWithoutChangingPreflightOutflow() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture,, NativeUsdTokenMock wrappedNative) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        GrantlineTypes.EvaluationResult memory result =
            _evaluateMixed(fixture, address(wrappedNative), 1 ether, 3 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeAmount == 1 ether);
        assert(result.nativeBalanceAfter == 4 ether);
        assert(result.nativeUsdValue == 200e8);
    }

    function test_preflightNativeUsdValuesProjectedNativeBalanceSeparately() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture,, NativeUsdTokenMock wrappedNative) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 200, false), 0, 0);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 1 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeUsdValue == 0);
        assert(result.nativeBalanceAfter == 4 ether);
        assert(result.nativeBalanceUsdValue == 200e8);

        result = _evaluateNative(fixture, 1.1 ether, 2);
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.PREFLIGHT_NATIVE_USD_BALANCE_BELOW_MINIMUM));
        assert(result.nativeBalanceUsdValue == 195e8);

        result = _evaluateToken(fixture, address(wrappedNative), 1 ether, 3);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeBalanceAfter == 5 ether);
        assert(result.nativeBalanceUsdValue == 250e8);
    }

    function test_preflightNativeUsdMinimumRoundsDownConservatively() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 200, false), 0, 0);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 1 ether + 1, 4);
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.PREFLIGHT_NATIVE_USD_BALANCE_BELOW_MINIMUM));
        assert(result.nativeBalanceUsdValue < 200e8);
    }

    function test_unrelatedTokensDoNotUseNativeFeed() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 1, false);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        NativeUsdTokenMock otherToken = new NativeUsdTokenMock(18);
        feed.setRevertLatestRoundData(true);

        GrantlineTypes.EvaluationResult memory result = _evaluateToken(fixture, address(otherToken), 10_000 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeUsdValue == 0);
    }

    function test_disabledRuleDoesNotReadConfiguredFeed() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        feed.setRevertLatestRoundData(true);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 1 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeUsdValue == 0);
    }

    function test_unsupportedDeploymentRejectsNativeUsdRules() public {
        Fixture memory fixture = _fixture();
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 100, false);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdValuationUnsupported.selector));
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 0, false), 0, 0);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdValuationUnsupported.selector));
        fixture.hub.createMandate(fixture.vault, address(0xA11CE), rules, _preflight(0, false, 0, false), 0, 0);

        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdValuationUnsupported.selector));
        fixture.hub.createChildMandate(fixture.mandateId, address(0xC11D), rules, _preflight(0, false, 0, false), 0, 0);
    }

    function test_unsupportedDeploymentRejectsNativeUsdPreflightRules() public {
        Fixture memory fixture = _fixture();
        GrantlineTypes.MandateRules memory rules = _rules(2 ether, false, 0, true);
        GrantlineTypes.PreflightRules memory preflight = _preflight(0, false, 100, false);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdValuationUnsupported.selector));
        fixture.hub.updateMandate(fixture.mandateId, rules, preflight, 0, 0);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdValuationUnsupported.selector));
        fixture.hub.createMandate(fixture.vault, address(0xA11CE), rules, preflight, 0, 0);

        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdValuationUnsupported.selector));
        fixture.hub.createChildMandate(fixture.mandateId, address(0xC11D), rules, preflight, 0, 0);
    }

    function test_nativeUsdRangeAndScaledThresholdAreValidated() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        rules.minNativeUsd = 201;
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.InvalidNativeUsdRange.selector, uint256(201), uint256(200))
        );
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 0, false), 0, 0);

        rules.minNativeUsd = 0;
        rules.maxNativeUsd = type(uint256).max / 1e8 + 1;
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.NativeUsdThresholdTooLarge.selector, rules.maxNativeUsd)
        );
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 0, false), 0, 0);
    }

    function test_nativeUsdPreflightThresholdIsValidated() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        uint256 threshold = type(uint256).max / 1e8 + 1;

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NativeUsdThresholdTooLarge.selector, threshold));
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, threshold, false), 0, 0);
    }

    function test_nativeUsdRulesIntersectAcrossLineage() public {
        GrantlineTypes.MandateRules memory rootRules = _nativeUsdRules(100, 500, true);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rootRules);
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);

        GrantlineTypes.MandateRules memory childRules = _nativeUsdRules(150, 400, true);
        fixtureVm.prank(fixture.agent);
        uint256 childId = fixture.hub
            .createChildMandate(fixture.mandateId, childAgent, childRules, _preflight(0, false, 0, false), 0, 0);

        GrantlineTypes.MandateRules memory grandchildRules = _nativeUsdRules(150, 400, true);
        grandchildRules.canDelegate = false;
        fixtureVm.prank(childAgent);
        uint256 grandchildId = fixture.hub
            .createChildMandate(childId, address(0xCAFE), grandchildRules, _preflight(0, false, 0, false), 0, 0);

        GrantlineTypes.MandateRules memory effective = fixture.hub.getEffectiveRules(grandchildId);
        assert(effective.minNativeUsd == 150);
        assert(effective.maxNativeUsd == 400);
        assert(effective.escalateNativeUsd);

        rootRules.maxNativeUsd = 300;
        fixture.hub.updateMandate(fixture.mandateId, rootRules, _preflight(0, false, 0, false), 0, 0);
        effective = fixture.hub.getEffectiveRules(grandchildId);
        assert(effective.maxNativeUsd == 300);
    }

    function test_childCannotBroadenNativeUsdAuthority() public {
        GrantlineTypes.MandateRules memory rootRules = _nativeUsdRules(100, 200, false);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rootRules);
        GrantlineTypes.MandateRules memory childRules = _nativeUsdRules(99, 201, true);

        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.ChildRulesExceedParent.selector, fixture.mandateId)
        );
        fixture.hub
            .createChildMandate(fixture.mandateId, address(0xC11D), childRules, _preflight(0, false, 0, false), 0, 0);
    }

    function test_preflightNativeUsdRulesIntersectAcrossLineage() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 200, false), 0, 0);
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);

        fixtureVm.prank(fixture.agent);
        uint256 childId = fixture.hub
        .createChildMandate(fixture.mandateId, childAgent, rules, _preflight(0, false, 300, false), 0, 0);
        GrantlineTypes.PreflightRules memory effective = fixture.hub.getEffectivePreflightRules(childId);
        assert(effective.minNativeUsdBalance == 300);
        assert(!effective.escalateNativeUsdBalance);

        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 400, false), 0, 0);
        effective = fixture.hub.getEffectivePreflightRules(childId);
        assert(effective.minNativeUsdBalance == 400);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.ChildPreflightRulesExceedParent.selector, fixture.mandateId)
        );
        fixture.hub.updateMandate(childId, rules, _preflight(0, false, 100, false), 0, 0);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.ChildPreflightRulesExceedParent.selector, fixture.mandateId)
        );
        fixture.hub.updateMandate(childId, rules, _preflight(0, false, 400, true), 0, 0);
    }

    function test_invalidFeedAnswersAndRuntimeDecimalsFailClosed() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        feed.setAnswer(0);
        _assertValuationUnavailable(_evaluateNative(fixture, 1 ether, 1));
        feed.setAnswer(-1);
        _assertValuationUnavailable(_evaluateNative(fixture, 1 ether, 2));
        feed.setAnswer(FIFTY_USD);
        feed.setRevertLatestRoundData(true);
        _assertValuationUnavailable(_evaluateNative(fixture, 1 ether, 3));
        feed.setRevertLatestRoundData(false);
        feed.setDecimals(7);
        _assertValuationUnavailable(_evaluateNative(fixture, 1 ether, 4));
        feed.setRevertDecimals(true);
        _assertValuationUnavailable(_evaluateNative(fixture, 1 ether, 5));
    }

    function test_adminWiringRejectsRuntimeFeedDecimalChanges() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        feed.setDecimals(7);

        NativeUsdEvaluatorV2 implementation = new NativeUsdEvaluatorV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.EVALUATOR_MODULE(), implementation: address(implementation), version: 1, data: ""
        });
        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                GrantlineAdmin.InvalidModuleRelationship.selector, bytes32("evaluator.nativeUsd.feedDecimals")
            )
        );
        fixture.admin.upgradeModules(upgrades);
    }

    function test_mixedPolicyViolationsRespectHardDenyPrecedence() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 50, false);
        rules.maxNativeAmount = 1 ether;
        rules.escalateNativeAmount = true;
        (Fixture memory fixture,,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);

        GrantlineTypes.EvaluationResult memory result = _evaluateNative(fixture, 2 ether, 1);
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM));

        rules.escalateNativeAmount = false;
        rules.escalateNativeUsd = true;
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 0, false), 0, 0);
        result = _evaluateNative(fixture, 2 ether, 2);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM));
    }

    function test_normalExecutionUsesCurrentPrice() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 100, false);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        // Build once while the action is below the cap, then move the oracle before execution.
        ActionTypes.ActionPlan memory plan = _nativePlanFor(fixture, 15e17, 1);
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, signature);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));

        feed.setAnswer(100e8);
        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);
    }

    function test_normalExecutionReevaluatesPreflightNativeUsdAtCurrentPrice() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 200, false), 0, 0);

        ActionTypes.ActionPlan memory plan = _nativePlanFor(fixture, 1 ether, 6);
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, signature);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));

        feed.setAnswer(40e8);
        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);
        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 6));
    }

    function test_approvedEscalationReevaluatesPreflightNativeUsdAtCurrentPrice() public {
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, 40e8, rules);
        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(0, false, 200, true), 0, 0);

        ActionTypes.ActionPlan memory plan = _nativePlanFor(fixture, 1 ether, 7);
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        assert(fixture.hub.evaluate(plan, signature).decision == uint8(MandateEvaluator.Decision.ESCALATE));
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.approveEscalation(digest);

        feed.setAnswer(FIFTY_USD);
        uint256 startingBalance = RECIPIENT.balance;
        fixture.hub.executeEscalated(digest);
        assert(RECIPIENT.balance == startingBalance + 1 ether);
    }

    function test_approvedEscalationReevaluatesPriceAndFeedAvailability() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 100, true);
        (Fixture memory fixture, NativeUsdFeedMock feed,) = _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        ActionTypes.ActionPlan memory plan = _nativePlanFor(fixture, 3 ether, 1);
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.approveEscalation(digest);

        feed.setAnswer(0);
        fixtureVm.expectRevert();
        fixture.hub.executeEscalated(digest);

        feed.setAnswer(20e8);
        uint256 startingBalance = RECIPIENT.balance;
        fixture.hub.executeEscalated(digest);
        assert(RECIPIENT.balance == startingBalance + 3 ether);
    }

    function test_evaluatorUpgradePreservesNativeUsdConfiguration() public {
        GrantlineTypes.MandateRules memory rules = _nativeUsdRules(0, 200, false);
        (Fixture memory fixture, NativeUsdFeedMock feed, NativeUsdTokenMock wrappedNative) =
            _nativeUsdFixture(FEED_DECIMALS, FIFTY_USD, rules);
        NativeUsdEvaluatorV2 implementation = new NativeUsdEvaluatorV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.EVALUATOR_MODULE(), implementation: address(implementation), version: 1, data: ""
        });

        fixture.admin.upgradeModules(upgrades);
        IEvaluator evaluator = IEvaluator(fixture.hub.evaluator());
        assert(evaluator.chainlinkNativeUsdFeed() == address(feed));
        assert(evaluator.chainlinkNativeUsdFeedDecimals() == FEED_DECIMALS);
        assert(evaluator.wrappedNative() == address(wrappedNative));
        assert(NativeUsdEvaluatorV2(fixture.hub.evaluator()).marker() == 2);
    }

    function test_nativeUsdConfigurationRejectsBadFeedOrWrapperMetadata() public {
        NativeUsdFeedMock feed = new NativeUsdFeedMock(FEED_DECIMALS, FIFTY_USD);
        NativeUsdTokenMock wrappedNative = new NativeUsdTokenMock(18);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateEvaluator.InvalidNativeUsdConfiguration.selector));
        this.deployHubWithNativeUsdForTest(address(feed), 7, address(wrappedNative));

        NativeUsdTokenMock wrongDecimalsWrapper = new NativeUsdTokenMock(6);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateEvaluator.InvalidNativeUsdConfiguration.selector));
        this.deployHubWithNativeUsdForTest(address(feed), FEED_DECIMALS, address(wrongDecimalsWrapper));

        NativeUsdFeedMock excessiveDecimalsFeed = new NativeUsdFeedMock(19, FIFTY_USD);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateEvaluator.InvalidNativeUsdConfiguration.selector));
        this.deployHubWithNativeUsdForTest(address(excessiveDecimalsFeed), 19, address(wrappedNative));
    }

    function deployHubWithNativeUsdForTest(address feed, uint8 feedDecimals, address wrappedNative) external {
        _deployHubWithNativeUsd(feed, feedDecimals, wrappedNative);
    }

    function _nativeUsdFixture(uint8 decimals, int256 answer, GrantlineTypes.MandateRules memory rules)
        private
        returns (Fixture memory fixture, NativeUsdFeedMock feed, NativeUsdTokenMock wrappedNative)
    {
        feed = new NativeUsdFeedMock(decimals, answer);
        wrappedNative = new NativeUsdTokenMock(18);
        fixture = _fixtureWithNativeUsd(address(feed), decimals, address(wrappedNative), rules);
    }

    function _nativeUsdRules(uint256 minimum, uint256 maximum, bool escalate)
        private
        pure
        returns (GrantlineTypes.MandateRules memory rules)
    {
        rules = _rules(0, false, 0, true);
        rules.minNativeUsd = minimum;
        rules.maxNativeUsd = maximum;
        rules.escalateNativeUsd = escalate;
    }

    function _evaluateNative(Fixture memory fixture, uint256 amount, uint256 nonce)
        private
        returns (GrantlineTypes.EvaluationResult memory)
    {
        ActionTypes.ActionPlan memory plan = _nativePlanFor(fixture, amount, nonce);
        return fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
    }

    function _evaluateToken(Fixture memory fixture, address token, uint256 amount, uint256 nonce)
        private
        returns (GrantlineTypes.EvaluationResult memory)
    {
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, nonce, block.timestamp + 100, _transferAction(token, RECIPIENT, amount)
        );
        return fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
    }

    function _evaluateMixed(
        Fixture memory fixture,
        address wrappedNative,
        uint256 nativeAmount,
        uint256 wrappedAmount,
        uint256 nonce
    ) private returns (GrantlineTypes.EvaluationResult memory) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), RECIPIENT, nativeAmount);
        actions[1] = _transferAction(wrappedNative, RECIPIENT, wrappedAmount);
        ActionTypes.ActionPlan memory plan =
            _plan(fixture.mandateId, fixture.agent, nonce, block.timestamp + 100, actions);
        return fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
    }

    function _nativePlanFor(Fixture memory fixture, uint256 amount, uint256 nonce)
        private
        view
        returns (ActionTypes.ActionPlan memory)
    {
        return _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            nonce,
            block.timestamp + 100,
            _transferAction(address(0), RECIPIENT, amount)
        );
    }

    function _assertValuationUnavailable(GrantlineTypes.EvaluationResult memory result) private pure {
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUATION_UNAVAILABLE));
    }
}
