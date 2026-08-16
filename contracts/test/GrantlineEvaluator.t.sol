// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {IUsdValueProvider, MandateEvaluator} from "../src/MandateEvaluator.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

interface GrantlineEvaluatorVm {
    function expectRevert() external;

    function warp(uint256 timestamp) external;
}

contract EvaluatorUsdProvider is IUsdValueProvider {
    mapping(address => uint256) public quote;
    mapping(address => bool) public available;
    bool public revertQuotes;

    function setQuote(address asset, uint256 amount) external {
        quote[asset] = amount;
        available[asset] = true;
    }

    function setUnavailable(address asset) external {
        available[asset] = false;
    }

    function setReverting(bool value) external {
        revertQuotes = value;
    }

    function quoteUsd(address asset, uint256) external view returns (uint256 usdAmount, bool isAvailable) {
        if (revertQuotes) revert();
        return (quote[asset], available[asset]);
    }
}

contract GrantlineEvaluatorTest is GrantlineTestFixture {
    GrantlineEvaluatorVm private constant evaluatorVm =
        GrantlineEvaluatorVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_planIdentityAndShapeFailures() public {
        Fixture memory fixture = _fixture();
        ActionTypes.Action memory validAction = _transferAction(address(0), address(0xBEEF), 1 ether);

        ActionTypes.ActionPlan memory plan = _singleActionPlan(0, fixture.agent, 1, 0, validAction);
        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, bytes(""));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.MANDATE_NOT_FOUND));

        plan.mandateId = fixture.mandateId;
        plan.agent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        result = fixture.hub.evaluate(plan, bytes(""));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.AGENT_MISMATCH));

        plan.agent = fixture.agent;
        result = fixture.hub.evaluate(plan, bytes(""));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SIGNATURE));

        ActionTypes.Action[] memory emptyActions = new ActionTypes.Action[](0);
        plan = _plan(fixture.mandateId, fixture.agent, 2, 0, emptyActions);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.EMPTY_PLAN));
    }

    function test_actionShapeFailures() public {
        Fixture memory fixture = _fixture();
        ActionTypes.Action memory action = _transferAction(address(0), address(0xBEEF), 1 ether);

        action.version = 2;
        _assertFailure(fixture, action, MandateEvaluator.FailureCode.INVALID_ACTION, 3);

        action.version = 1;
        action.parameters = hex"01";
        _assertFailure(fixture, action, MandateEvaluator.FailureCode.INVALID_ACTION_PARAMETERS, 4);

        action.parameters =
            abi.encode(ActionTypes.TransferParameters({asset: address(0), recipient: address(0), amount: 1 ether}));
        _assertFailure(fixture, action, MandateEvaluator.FailureCode.INVALID_RECIPIENT, 5);

        action.parameters =
            abi.encode(ActionTypes.TransferParameters({asset: address(0), recipient: address(0xBEEF), amount: 0}));
        _assertFailure(fixture, action, MandateEvaluator.FailureCode.INVALID_AMOUNT, 6);
    }

    function test_deadlineBoundaryAndRevocationFailures() public {
        Fixture memory fixture = _fixture();
        uint256 deadline = block.timestamp + 10;
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 8, deadline, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        evaluatorVm.warp(deadline);
        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, signature);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));

        evaluatorVm.warp(deadline + 1);
        result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.EXPIRED));

        fixture.hub.revokeMandate(fixture.mandateId);
        result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.MANDATE_INACTIVE));
    }

    function test_pausedMandateAndVaultFailures() public {
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 25, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        fixture.hub.pauseMandate(fixture.mandateId);
        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.MANDATE_PAUSED));

        fixture.hub.unpauseMandate(fixture.mandateId);
        fixture.hub.pauseVault(fixture.vault);
        result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.VAULT_PAUSED));

        fixture.hub.unpauseVault(fixture.vault);
        result = fixture.hub.evaluate(plan, signature);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
    }

    function test_nativeAggregationAndBoundaries() public {
        GrantlineTypes.MandateRules memory rules = _rules(2 ether, false, 1 ether, 0, false, true);
        Fixture memory fixture = _fixtureWithRules(rules, _preflight(0, false), address(0), true);

        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 9, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));

        plan.nonce = 10;
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 0.5 ether);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_AMOUNT_BELOW_MINIMUM));

        plan.nonce = 11;
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2.1 ether);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM));

        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        actions[1] = _transferAction(address(0), address(0xCAFE), 1 ether);
        plan = _plan(fixture.mandateId, fixture.agent, 12, 0, actions);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeAmount == 2 ether);

        actions[1] = _transferAction(address(0), address(0xCAFE), type(uint256).max);
        plan = _plan(fixture.mandateId, fixture.agent, 13, 0, actions);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.AMOUNT_OVERFLOW));
    }

    function test_nativeAndPreflightEscalationModes() public {
        GrantlineTypes.MandateRules memory rules = _rules(2 ether, true, 0, 0, false, true);
        Fixture memory fixture = _fixtureWithRules(rules, _preflight(0, false), address(0), true);
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 14, 0, _transferAction(address(0), address(0xBEEF), 2.1 ether)
        );
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.ESCALATE));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM));

        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(6 ether, false), 0, 0);
        plan.nonce = 15;
        plan.actions[0] = _transferAction(address(0xCAFE), address(0xBEEF), 1);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.PREFLIGHT_NATIVE_BALANCE_BELOW_MINIMUM));
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));

        fixture.hub.updateMandate(fixture.mandateId, rules, _preflight(6 ether, true), 0, 0);
        plan.nonce = 16;
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.ESCALATE));
    }

    function test_usdLimitsAndUnavailableValuations() public {
        EvaluatorUsdProvider provider = new EvaluatorUsdProvider();
        provider.setQuote(address(0), 2e18);
        address token = address(0xCAFE);
        provider.setQuote(token, 5e17);

        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, 2e18, false, true);
        rules.maxUsdAmount = 3e18;
        Fixture memory fixture = _fixtureWithRules(rules, _preflight(0, false), address(provider), false);

        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), address(0xBEEF), 1);
        actions[1] = _transferAction(token, address(0xD00D), 1);
        ActionTypes.ActionPlan memory plan = _plan(fixture.mandateId, fixture.agent, 17, 0, actions);
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.usdAmount == 2.5e18);

        provider.setQuote(address(0), 4e18);
        plan.nonce = 18;
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM));

        provider.setUnavailable(token);
        plan.nonce = 19;
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.USD_VALUATION_UNAVAILABLE));

        GrantlineTypes.MandateRules memory skipRules = rules;
        Fixture memory skipFixture = _fixtureWithRules(skipRules, _preflight(0, false), address(provider), true);
        plan = _plan(skipFixture.mandateId, skipFixture.agent, 20, 0, actions);
        result = skipFixture.hub.evaluate(plan, _sign(skipFixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.usdLimitSkipped);
        assert(result.usdAmount == 4e18);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.USD_AMOUNT_ABOVE_MAXIMUM));

        provider.setReverting(true);
        plan = _plan(skipFixture.mandateId, skipFixture.agent, 21, 0, actions);
        result = skipFixture.hub.evaluate(plan, _sign(skipFixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.usdLimitSkipped);
    }

    function test_usdOverflowAndMinimum() public {
        EvaluatorUsdProvider provider = new EvaluatorUsdProvider();
        provider.setQuote(address(0), 2e18);
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, 3e18, false, true);
        Fixture memory fixture = _fixtureWithRules(rules, _preflight(0, false), address(provider), false);
        ActionTypes.ActionPlan memory plan =
            _singleActionPlan(fixture.mandateId, fixture.agent, 22, 0, _transferAction(address(0), address(0xBEEF), 1));
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.USD_AMOUNT_BELOW_MINIMUM));

        provider.setQuote(address(0), type(uint256).max);
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), address(0xBEEF), 1);
        actions[1] = _transferAction(address(0), address(0xD00D), 1);
        plan = _plan(fixture.mandateId, fixture.agent, 24, 0, actions);
        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.USD_AMOUNT_OVERFLOW));
    }

    function _assertFailure(
        Fixture memory fixture,
        ActionTypes.Action memory action,
        MandateEvaluator.FailureCode expected,
        uint256 nonce
    ) private {
        ActionTypes.ActionPlan memory plan = _singleActionPlan(fixture.mandateId, fixture.agent, nonce, 0, action);
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(expected));
    }
}
