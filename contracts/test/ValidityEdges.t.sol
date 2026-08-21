// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {TestFixture} from "./TestFixture.sol";

contract ValidityEdgesTest is TestFixture {
    function test_localValidityWindowsAreValidatedAndInclusive() public {
        Fixture memory fixture = _fixture();
        uint64 validAfter = uint64(block.timestamp + 10);
        uint64 validUntil = uint64(block.timestamp + 20);

        uint256 mandateId = fixture.hub
            .createMandate(
                fixture.vault,
                fixture.agent,
                _rules(2 ether, false, 0, true),
                _preflight(0, false, 0, false),
                validAfter,
                validUntil
            );
        GrantlineTypes.MandateView memory mandate = fixture.hub.getMandate(mandateId);
        assert(mandate.validAfter == validAfter);
        assert(mandate.validUntil == validUntil);
        (uint64 effectiveAfter, uint64 effectiveUntil) = fixture.hub.getEffectiveValidityWindow(mandateId);
        assert(effectiveAfter == validAfter);
        assert(effectiveUntil == validUntil);
        assert(!fixture.hub.isLineageActive(mandateId));

        fixtureVm.warp(validAfter);
        assert(fixture.hub.isLineageActive(mandateId));
        fixtureVm.warp(validUntil);
        assert(fixture.hub.isLineageActive(mandateId));
        fixtureVm.warp(validUntil + 1);
        assert(!fixture.hub.isLineageActive(mandateId));

        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.InvalidValidityWindow.selector, validUntil, validAfter)
        );
        fixture.hub
            .createMandate(
                fixture.vault,
                fixture.agent,
                _rules(2 ether, false, 0, true),
                _preflight(0, false, 0, false),
                validUntil,
                validAfter
            );
    }

    function test_effectiveValidityUsesLineageIntersectionAndSupportsNonOverlap() public {
        Fixture memory fixture = _fixtureWithRules(_rules(2 ether, false, 0, true), _preflight(0, false, 0, false));
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        uint256 childId;
        fixtureVm.prank(fixture.agent);
        childId = fixture.hub
            .createChildMandate(
                fixture.mandateId, childAgent, _rules(1 ether, false, 0, true), _preflight(0, false, 0, false), 0, 0
            );

        fixtureVm.prank(childAgent);
        uint256 grandchildId = fixture.hub
            .createChildMandate(
                childId,
                fixtureVm.addr(0xCAFE),
                _rules(0.5 ether, false, 0, false),
                _preflight(0, false, 0, false),
                0,
                0
            );

        uint64 nowTimestamp = uint64(block.timestamp);
        uint64 rootAfter = nowTimestamp + 10;
        uint64 rootUntil = nowTimestamp + 100;
        uint64 childAfter = nowTimestamp + 20;
        uint64 childUntil = nowTimestamp + 80;

        fixtureVm.prank(childAgent);
        fixture.hub
            .updateMandate(
                grandchildId,
                _rules(0.5 ether, false, 0, false),
                _preflight(0, false, 0, false),
                nowTimestamp + 5,
                nowTimestamp + 90
            );
        fixtureVm.prank(fixture.agent);
        fixture.hub
            .updateMandate(
                childId, _rules(1 ether, false, 0, true), _preflight(0, false, 0, false), childAfter, childUntil
            );
        fixture.hub
            .updateMandate(
                fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false, 0, false), rootAfter, rootUntil
            );

        (uint64 effectiveAfter, uint64 effectiveUntil) = fixture.hub.getEffectiveValidityWindow(grandchildId);
        assert(effectiveAfter == childAfter);
        assert(effectiveUntil == childUntil);
        assert(!fixture.hub.isLineageActive(grandchildId));
        fixtureVm.warp(childAfter);
        assert(fixture.hub.isLineageActive(grandchildId));
        fixtureVm.warp(childUntil + 1);
        assert(!fixture.hub.isLineageActive(grandchildId));

        fixture.hub
            .updateMandate(
                grandchildId,
                _rules(0.5 ether, false, 0, false),
                _preflight(0, false, 0, false),
                nowTimestamp + 200,
                nowTimestamp + 300
            );
        (effectiveAfter, effectiveUntil) = fixture.hub.getEffectiveValidityWindow(grandchildId);
        assert(effectiveAfter == nowTimestamp + 200);
        assert(effectiveUntil == childUntil);
        assert(!fixture.hub.isLineageActive(grandchildId));
    }

    function test_evaluatorSeparatesMandateWindowsFromPlanDeadlines() public {
        Fixture memory fixture = _fixture();
        uint64 validAfter = uint64(block.timestamp + 10);
        uint256 mandateId = fixture.hub
            .createMandate(
                fixture.vault,
                fixture.agent,
                _rules(2 ether, false, 0, true),
                _preflight(0, false, 0, false),
                validAfter,
                0
            );
        ActionTypes.ActionPlan memory plan =
            _singleActionPlan(mandateId, fixture.agent, 101, 0, _transferAction(address(0), address(0xBEEF), 1 ether));
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.MANDATE_NOT_YET_VALID));

        fixtureVm.warp(validAfter);
        result = fixture.hub.evaluate(plan, signature);
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));

        fixture.hub
            .updateMandate(
                mandateId,
                _rules(2 ether, false, 0, true),
                _preflight(0, false, 0, false),
                0,
                uint64(block.timestamp - 1)
            );
        result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.MANDATE_EXPIRED));

        fixture.hub.updateMandate(mandateId, _rules(2 ether, false, 0, true), _preflight(0, false, 0, false), 0, 0);
        plan.deadline = block.timestamp - 1;
        signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        result = fixture.hub.evaluate(plan, signature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.EXPIRED));
    }

    function test_controllerCanRecoverExpiredLineageButParentAgentCannotAdministerChild() public {
        Fixture memory fixture = _fixture();
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        fixtureVm.prank(fixture.agent);
        uint256 childId = fixture.hub
            .createChildMandate(
                fixture.mandateId, childAgent, _rules(1 ether, false, 0, false), _preflight(0, false, 0, false), 0, 0
            );

        fixtureVm.warp(100);
        fixture.hub
            .updateMandate(fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false, 0, false), 0, 99);
        assert(!fixture.hub.isLineageActive(childId));

        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                MandateRegistry.MandateLineageInactive.selector, fixture.mandateId, fixture.mandateId
            )
        );
        fixture.hub.updateMandate(childId, _rules(1 ether, false, 0, false), _preflight(0, false, 0, false), 0, 0);

        fixture.hub.updateMandate(childId, _rules(1 ether, false, 0, false), _preflight(0, false, 0, false), 0, 0);
        fixture.hub
            .updateMandate(fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false, 0, false), 0, 0);
        assert(fixture.hub.isLineageActive(childId));
    }

    function test_escalationsRecheckMandateWindowsAtApprovalAndExecution() public {
        Fixture memory fixture = _fixtureWithRules(_rules(1 ether, true, 0, true), _preflight(0, false, 0, false));
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 201, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub
            .updateMandate(
                fixture.mandateId,
                _rules(1 ether, true, 0, true),
                _preflight(0, false, 0, false),
                0,
                uint64(block.timestamp)
            );
        fixtureVm.warp(block.timestamp + 1);

        fixtureVm.expectRevert(abi.encodeWithSelector(EscalationManager.MandateExpired.selector, fixture.mandateId));
        fixture.hub.approveEscalation(digest);
        fixture.hub.denyEscalation(digest);

        Fixture memory approvedFixture =
            _fixtureWithRules(_rules(1 ether, true, 0, true), _preflight(0, false, 0, false));
        ActionTypes.ActionPlan memory approvedPlan = _singleActionPlan(
            approvedFixture.mandateId,
            approvedFixture.agent,
            202,
            0,
            _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory approvedSignature = _sign(approvedFixture.hub, approvedPlan, FIXTURE_AGENT_KEY);
        bytes32 approvedDigest = approvedFixture.hub.submitEscalation(approvedPlan, approvedSignature);
        approvedFixture.hub.approveEscalation(approvedDigest);
        approvedFixture.hub
            .updateMandate(
                approvedFixture.mandateId,
                _rules(1 ether, true, 0, true),
                _preflight(0, false, 0, false),
                0,
                uint64(block.timestamp)
            );
        fixtureVm.warp(block.timestamp + 1);

        fixtureVm.expectRevert();
        approvedFixture.hub.executeEscalated(approvedDigest);
        assert(approvedFixture.hub.escalationStatus(approvedDigest) == 2);
        assert(
            !MandateRegistry(approvedFixture.hub.registry())
                .nonceUsed(approvedFixture.mandateId, approvedFixture.agent, 202)
        );
    }
}
