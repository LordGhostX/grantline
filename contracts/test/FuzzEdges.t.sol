// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {TestFixture} from "./TestFixture.sol";

contract FuzzEdgesTest is TestFixture {
    function testFuzz_nativeLimitDecisionMatchesAggregatedAmount(uint256 amount) public {
        amount = amount % 3 ether + 1;
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 71, 0, _transferAction(address(0), address(0xBEEF), amount)
        );
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        assert(result.nativeAmount == amount);
        if (amount <= 2 ether) {
            assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
            assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NONE));
        } else {
            assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
            assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_AMOUNT_ABOVE_MAXIMUM));
        }
    }

    function testFuzz_actionPlanDigestCommitsToEveryPlanField(uint256 amount, uint256 nonce) public {
        amount = amount % 2 ether + 1;
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory first = _singleActionPlan(
            fixture.mandateId, fixture.agent, nonce, 0, _transferAction(address(0), address(0xBEEF), amount)
        );
        ActionTypes.ActionPlan memory changed = _singleActionPlan(
            fixture.mandateId, fixture.agent, nonce, 0, _transferAction(address(0), address(0xBEEF), amount + 1)
        );
        assert(fixture.hub.actionDigest(first) != fixture.hub.actionDigest(changed));

        changed.nonce = nonce == type(uint256).max ? nonce - 1 : nonce + 1;
        assert(fixture.hub.actionDigest(first) != fixture.hub.actionDigest(changed));
        changed.nonce = nonce;
        changed.deadline = 1;
        assert(fixture.hub.actionDigest(first) != fixture.hub.actionDigest(changed));
    }

    function testFuzz_successfulExecutionConsumesAnyUnusedNonce(uint256 nonce) public {
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, nonce, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, nonce));
    }

    function testFuzz_deadlineBoundaryIsInclusive(uint256 offset) public {
        fixtureVm.warp(100);
        Fixture memory fixture = _fixture();
        uint256 deadline = offset % 2 == 0 ? 100 : 99;
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 72, deadline, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        if (deadline == 100) {
            assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        } else {
            assert(result.failureCode == uint8(MandateEvaluator.FailureCode.EXPIRED));
        }
    }
}
