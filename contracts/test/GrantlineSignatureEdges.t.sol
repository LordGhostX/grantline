// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract GrantlineSignatureEdgesTest is GrantlineTestFixture {
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant ACTION_TYPEHASH = keccak256("Action(uint8 actionType,uint8 version,bytes parameters)");
    bytes32 private constant ACTION_PLAN_TYPEHASH = keccak256(
        "ActionPlan(uint256 mandateId,address agent,uint256 nonce,uint256 deadline,Action[] actions)Action(uint8 actionType,uint8 version,bytes parameters)"
    );

    function test_actionDigestMatchesIndependentCanonicalReference() public {
        Fixture memory fixture = _fixture();
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        actions[1] = _transferAction(address(0xCAFE), address(0xD00D), 2 ether);
        ActionTypes.ActionPlan memory plan = _plan(fixture.mandateId, fixture.agent, 73, 1234, actions);

        bytes32 originalDigest = fixture.hub.actionDigest(plan);
        assert(originalDigest == _referenceDigest(fixture.hub, plan));

        ActionTypes.Action memory first = plan.actions[0];
        plan.actions[0] = plan.actions[1];
        plan.actions[1] = first;
        bytes32 reorderedDigest = fixture.hub.actionDigest(plan);
        assert(reorderedDigest == _referenceDigest(fixture.hub, plan));
        assert(reorderedDigest != originalDigest);
    }

    function test_actionDigestBindsPlanFieldsAndGrantlineProxy() public {
        Fixture memory firstFixture = _fixture();
        Fixture memory secondFixture = _fixture();
        ActionTypes.ActionPlan memory firstPlan = _singleActionPlan(
            firstFixture.mandateId, firstFixture.agent, 74, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        ActionTypes.ActionPlan memory secondPlan = _singleActionPlan(
            secondFixture.mandateId, secondFixture.agent, 74, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );

        bytes32 originalDigest = firstFixture.hub.actionDigest(firstPlan);
        assert(originalDigest != secondFixture.hub.actionDigest(secondPlan));

        firstPlan.mandateId += 1;
        assert(originalDigest != firstFixture.hub.actionDigest(firstPlan));
        firstPlan.mandateId -= 1;
        firstPlan.agent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        assert(originalDigest != firstFixture.hub.actionDigest(firstPlan));
        firstPlan.agent = firstFixture.agent;
        firstPlan.nonce += 1;
        assert(originalDigest != firstFixture.hub.actionDigest(firstPlan));
        firstPlan.nonce -= 1;
        firstPlan.deadline = 1;
        assert(originalDigest != firstFixture.hub.actionDigest(firstPlan));
    }

    function test_canonicalSignatureEvaluatesAndExecutes() public {
        Fixture memory fixture = _fixture();
        address recipient = address(0xBEEF);
        ActionTypes.ActionPlan memory plan =
            _singleActionPlan(fixture.mandateId, fixture.agent, 75, 0, _transferAction(address(0), recipient, 1 ether));
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, signature);

        assert(fixture.hub.actionDigest(plan) == _referenceDigest(fixture.hub, plan));
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NONE));

        fixture.hub.execute(plan, signature);
        assert(recipient.balance == 1 ether);
    }

    function test_invalidSignatureFormsRemainEvaluationFailures() public {
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 76, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );

        GrantlineTypes.EvaluationResult memory result = fixture.hub.evaluate(plan, bytes(""));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SIGNATURE));

        result = fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_OTHER_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SIGNATURE));

        bytes memory malformedSignature = new bytes(64);
        result = fixture.hub.evaluate(plan, malformedSignature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SIGNATURE));

        bytes memory invalidVSignature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        invalidVSignature[64] = bytes1(uint8(29));
        result = fixture.hub.evaluate(plan, invalidVSignature);
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SIGNATURE));
    }

    function _referenceDigest(Grantline hub, ActionTypes.ActionPlan memory plan) private view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256("Grantline"), keccak256("1"), block.chainid, address(hub))
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, _referenceActionPlanHash(plan)));
    }

    function _referenceActionPlanHash(ActionTypes.ActionPlan memory plan) private pure returns (bytes32) {
        bytes32[] memory actionHashes = new bytes32[](plan.actions.length);
        for (uint256 index; index < plan.actions.length; index++) {
            actionHashes[index] = keccak256(
                abi.encode(
                    ACTION_TYPEHASH,
                    uint8(plan.actions[index].actionType),
                    plan.actions[index].version,
                    keccak256(plan.actions[index].parameters)
                )
            );
        }

        return keccak256(
            abi.encode(
                ACTION_PLAN_TYPEHASH,
                plan.mandateId,
                plan.agent,
                plan.nonce,
                plan.deadline,
                keccak256(abi.encodePacked(actionHashes))
            )
        );
    }
}
