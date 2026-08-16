// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract GrantlineNonceRegistryV2 is MandateRegistry {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineNonceCancellationTest is GrantlineTestFixture {
    event NonceCancelled(
        uint256 indexed mandateId, address indexed agent, uint256 indexed nonce, address cancelledBy, uint64 cancelledAt
    );

    function test_agentCancelsOutstandingPlanAndBlocksEveryReuse() public {
        fixtureVm.warp(1_000);
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 100, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        GrantlineTypes.EvaluationResult memory evaluation = fixture.hub.evaluate(plan, signature);
        assert(evaluation.decision == uint8(MandateEvaluator.Decision.ALLOW));

        fixtureVm.expectEmit(true, true, true, true);
        emit NonceCancelled(fixture.mandateId, fixture.agent, 100, fixture.agent, uint64(block.timestamp));
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 100);

        (bool used, bytes32 reservation) = fixture.hub.getNonceState(fixture.mandateId, 100);
        assert(used);
        assert(reservation == bytes32(0));

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultExecutor.NonceAlreadyUsed.selector, fixture.mandateId, fixture.agent, 100)
        );
        fixture.hub.execute(plan, signature);

        plan.actions[0] = _transferAction(address(0), address(0xCAFE), 1 ether);
        bytes memory changedSignature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultExecutor.NonceAlreadyUsed.selector, fixture.mandateId, fixture.agent, 100)
        );
        fixture.hub.execute(plan, changedSignature);
        assert(address(0xBEEF).balance == 0);
        assert(address(0xCAFE).balance == 0);
    }

    function test_controllerCanCancelAndFormerControllerCannot() public {
        Fixture memory fixture = _fixture();
        fixture.hub.cancelNonce(fixture.mandateId, 101);
        (bool used,) = fixture.hub.getNonceState(fixture.mandateId, 101);
        assert(used);

        address nextController = address(0xCAFE);
        fixture.admin.setVaultController(fixture.vault, nextController);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.NotNonceCanceller.selector, fixture.mandateId, address(this))
        );
        fixture.hub.cancelNonce(fixture.mandateId, 102);

        fixtureVm.prank(nextController);
        fixture.hub.cancelNonce(fixture.mandateId, 102);
        (used,) = fixture.hub.getNonceState(fixture.mandateId, 102);
        assert(used);
    }

    function test_parentAgentAndUnrelatedCallerCannotCancelChildNonce() public {
        Fixture memory fixture = _fixture();
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        fixtureVm.prank(fixture.agent);
        uint256 childId = fixture.hub
            .createChildMandate(
                fixture.mandateId, childAgent, _rules(1 ether, false, 0, false), _preflight(0, false), 0, 0
            );

        fixtureVm.prank(address(0xD00D));
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotNonceCanceller.selector, childId, address(0xD00D)));
        fixture.hub.cancelNonce(childId, 103);

        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotNonceCanceller.selector, childId, fixture.agent));
        fixture.hub.cancelNonce(childId, 103);

        fixtureVm.prank(childAgent);
        fixture.hub.cancelNonce(childId, 103);
        (bool used,) = fixture.hub.getNonceState(childId, 103);
        assert(used);
    }

    function test_rejectsMissingUsedCancelledAndReservedNonces() public {
        Fixture memory fixture = _fixture();

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotFound.selector, 0));
        fixture.hub.cancelNonce(0, 104);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotFound.selector, 2));
        fixture.hub.getNonceState(2, 104);

        ActionTypes.ActionPlan memory usedPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 104, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        fixture.hub.execute(usedPlan, _sign(fixture.hub, usedPlan, FIXTURE_AGENT_KEY));
        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.NonceAlreadyUsed.selector, fixture.mandateId, fixture.agent, 104)
        );
        fixture.hub.cancelNonce(fixture.mandateId, 104);

        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 105);
        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.NonceAlreadyUsed.selector, fixture.mandateId, fixture.agent, 105)
        );
        fixture.hub.cancelNonce(fixture.mandateId, 105);

        Fixture memory escalating = _fixtureWithRules(_rules(1 ether, true, 0, true), _preflight(0, false));
        ActionTypes.ActionPlan memory escalationPlan = _singleActionPlan(
            escalating.mandateId, escalating.agent, 106, 0, _transferAction(address(0), address(0xCAFE), 2 ether)
        );
        bytes memory escalationSignature = _sign(escalating.hub, escalationPlan, FIXTURE_AGENT_KEY);
        bytes32 digest = escalating.hub.submitEscalation(escalationPlan, escalationSignature);
        (bool reservedUsed, bytes32 reservation) = escalating.hub.getNonceState(escalating.mandateId, 106);
        assert(!reservedUsed);
        assert(reservation == digest);

        fixtureVm.prank(escalating.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                MandateRegistry.NonceReserved.selector, escalating.mandateId, escalating.agent, 106, digest
            )
        );
        escalating.hub.cancelNonce(escalating.mandateId, 106);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                MandateRegistry.NonceReserved.selector, escalating.mandateId, escalating.agent, 106, digest
            )
        );
        escalating.hub.cancelNonce(escalating.mandateId, 106);
    }

    function test_cancelledEscalatablePlanCannotCreateReservation() public {
        Fixture memory fixture = _fixtureWithRules(_rules(1 ether, true, 0, true), _preflight(0, false));
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 107, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.actionDigest(plan);

        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 107);
        GrantlineTypes.EvaluationResult memory evaluation = fixture.hub.evaluate(plan, signature);
        assert(evaluation.decision == uint8(MandateEvaluator.Decision.ESCALATE));

        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.NonceAlreadyUsed.selector, fixture.mandateId, fixture.agent, 107)
        );
        fixture.hub.submitEscalation(plan, signature);
        (, bytes32 reservation) = fixture.hub.getNonceState(fixture.mandateId, 107);
        assert(reservation == bytes32(0));
        fixtureVm.expectRevert(abi.encodeWithSelector(EscalationManager.EscalationNotFound.selector, digest));
        fixture.hub.getEscalation(digest);
    }

    function test_cancellationRemainsAvailableAcrossRecoveryStates() public {
        fixtureVm.warp(1_000);
        Fixture memory fixture = _fixture();

        fixture.hub.pauseVault(fixture.vault);
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 108);
        fixture.hub.unpauseVault(fixture.vault);
        _assertCancelledPlanCannotExecute(fixture, 108);

        fixture.hub.pauseMandate(fixture.mandateId);
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 109);
        fixture.hub.unpauseMandate(fixture.mandateId);
        _assertCancelledPlanCannotExecute(fixture, 109);

        fixture.hub.updateMandate(fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false), 2_000, 0);
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 110);
        fixture.hub.updateMandate(fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false), 0, 0);
        _assertCancelledPlanCannotExecute(fixture, 110);

        fixture.hub.updateMandate(fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false), 0, 999);
        fixture.hub.cancelNonce(fixture.mandateId, 111);
        fixture.hub.updateMandate(fixture.mandateId, _rules(2 ether, false, 0, true), _preflight(0, false), 0, 0);
        _assertCancelledPlanCannotExecute(fixture, 111);

        fixture.hub.revokeMandate(fixture.mandateId);
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 112);
        (bool used,) = fixture.hub.getNonceState(fixture.mandateId, 112);
        assert(used);
    }

    function test_nonceCancellationIsIsolatedByMandateAndAgent() public {
        Fixture memory fixture = _fixture();
        uint256 secondRootId = fixture.hub
            .createMandate(fixture.vault, fixture.agent, _rules(1 ether, false, 0, false), _preflight(0, false), 0, 0);
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        fixtureVm.prank(fixture.agent);
        uint256 childId = fixture.hub
            .createChildMandate(
                fixture.mandateId, childAgent, _rules(1 ether, false, 0, false), _preflight(0, false), 0, 0
            );

        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 113);
        (bool secondRootUsed,) = fixture.hub.getNonceState(secondRootId, 113);
        (bool childUsed,) = fixture.hub.getNonceState(childId, 113);
        assert(!secondRootUsed);
        assert(!childUsed);

        ActionTypes.ActionPlan memory childPlan =
            _singleActionPlan(childId, childAgent, 113, 0, _transferAction(address(0), address(0xBEEF), 1 ether));
        fixture.hub.execute(childPlan, _sign(fixture.hub, childPlan, FIXTURE_OTHER_AGENT_KEY));
        assert(address(0xBEEF).balance == 1 ether);
    }

    function test_onlyGrantlineCanCallRegistryCancellation() public {
        Fixture memory fixture = _fixture();
        MandateRegistry registry = MandateRegistry(fixture.hub.registry());
        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.NotGrantline.selector, fixture.agent));
        registry.cancelNonce(fixture.mandateId, fixture.agent, 114);

        address unrelatedCaller = address(0xCAFE);
        fixtureVm.prank(address(fixture.hub));
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.NotNonceCanceller.selector, fixture.mandateId, unrelatedCaller)
        );
        registry.cancelNonce(fixture.mandateId, unrelatedCaller, 114);
    }

    function test_cancelledNonceSurvivesRegistryUpgrade() public {
        Fixture memory fixture = _fixture();
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, 115);

        GrantlineNonceRegistryV2 implementation = new GrantlineNonceRegistryV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(implementation), version: 1, data: ""
        });
        fixture.admin.upgradeModules(upgrades);

        assert(GrantlineNonceRegistryV2(fixture.hub.registry()).marker() == 2);
        (bool used, bytes32 reservation) = fixture.hub.getNonceState(fixture.mandateId, 115);
        assert(used);
        assert(reservation == bytes32(0));
        _assertCancelledPlanCannotExecute(fixture, 115);
    }

    function testFuzz_agentCanCancelAnyAvailableNonce(uint256 nonce) public {
        Fixture memory fixture = _fixture();
        fixtureVm.prank(fixture.agent);
        fixture.hub.cancelNonce(fixture.mandateId, nonce);
        (bool used, bytes32 reservation) = fixture.hub.getNonceState(fixture.mandateId, nonce);
        assert(used);
        assert(reservation == bytes32(0));
    }

    function _assertCancelledPlanCannotExecute(Fixture memory fixture, uint256 nonce) private {
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, nonce, 0, _transferAction(address(0), address(0xBEEF), 1 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultExecutor.NonceAlreadyUsed.selector, fixture.mandateId, fixture.agent, nonce)
        );
        fixture.hub.execute(plan, signature);
    }
}
