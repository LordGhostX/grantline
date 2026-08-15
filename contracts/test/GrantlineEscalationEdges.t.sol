// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract GrantlineEscalationManagerV2 is EscalationManager {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineEscalationRegistryV2 is MandateRegistry {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineEscalationExecutorV2 is VaultExecutor {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineEscalationEdgesTest is GrantlineTestFixture {
    function test_submitRecordsFullPlanAndSubmittingCaller() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 51, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        GrantlineTypes.Escalation memory escalation = fixture.hub.getEscalation(digest);

        assert(escalation.status == uint8(EscalationManager.Status.PENDING));
        assert(escalation.submittedBy == address(this));
        assert(escalation.plan.mandateId == plan.mandateId);
        assert(escalation.plan.actions.length == 1);
        assert(escalation.signature.length == signature.length);
        assert(EscalationManager(fixture.hub.escalationManager()).statusOf(digest) == EscalationManager.Status.PENDING);
        assert(
            EscalationManager(fixture.hub.escalationManager()).reservedDigest(fixture.mandateId, fixture.agent, 51)
                == digest
        );
        assert(MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 51) == digest);
    }

    function test_onlyTheVaultControllerCanApproveOrDeny() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 52, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);

        fixtureVm.prank(address(0xCAFE));
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, fixture.vault, address(0xCAFE)));
        fixture.hub.approveEscalation(digest);

        fixtureVm.prank(address(0xCAFE));
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, fixture.vault, address(0xCAFE)));
        fixture.hub.denyEscalation(digest);
    }

    function test_escalationTransitionsAreOneWay() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 53, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);

        fixture.hub.approveEscalation(digest);
        fixture.hub.executeEscalated(digest);
        fixtureVm.expectRevert();
        fixture.hub.approveEscalation(digest);
        fixtureVm.expectRevert();
        fixture.hub.denyEscalation(digest);

        fixtureVm.expectRevert();
        fixture.hub.executeEscalated(digest);
    }

    function test_deniedEscalationCannotExecuteAndKeepsReservation() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 54, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.denyEscalation(digest);

        fixtureVm.expectRevert();
        fixture.hub.executeEscalated(digest);
        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.DENIED));
        assert(MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 54) == digest);
    }

    function test_pausedMandateBlocksEscalationApprovalButAllowsDenial() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 62, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);

        fixture.hub.pauseMandate(fixture.mandateId);
        fixtureVm.expectRevert(abi.encodeWithSelector(EscalationManager.MandatePaused.selector, fixture.mandateId));
        fixture.hub.approveEscalation(digest);
        fixture.hub.denyEscalation(digest);

        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.DENIED));
        assert(MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 62) == digest);
    }

    function test_pausedVaultBlocksEscalationApprovalButAllowsDenial() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 63, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);

        fixture.hub.pauseVault(fixture.vault);
        fixtureVm.expectRevert(abi.encodeWithSelector(EscalationManager.VaultPaused.selector, fixture.vault));
        fixture.hub.approveEscalation(digest);
        fixture.hub.denyEscalation(digest);

        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.DENIED));
        assert(MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 63) == digest);
    }

    function test_approvedEscalationSurvivesVaultPauseAndRetriesAfterUnpause() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 64, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.approveEscalation(digest);

        fixture.hub.pauseVault(fixture.vault);
        fixtureVm.expectRevert();
        fixture.hub.executeEscalated(digest);
        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.APPROVED));
        assert(MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 64) == digest);

        fixture.hub.unpauseVault(fixture.vault);
        fixture.hub.executeEscalated(digest);
        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.EXECUTED));
        assert(address(0xBEEF).balance == 2 ether);
    }

    function test_pendingReservationBlocksNormalExecutionEvenAfterDenial() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 55, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);

        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);
        fixture.hub.denyEscalation(digest);
        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);
        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 55));
    }

    function test_approvedExecutionReevaluatesCurrentMandateAndPreservesApprovalOnDeny() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 56, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.approveEscalation(digest);

        fixture.hub.updateMandate(fixture.mandateId, _rules(1 ether, false, 0, 0, false, true), _preflight(0, false));
        fixtureVm.expectRevert();
        fixture.hub.executeEscalated(digest);

        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.APPROVED));
        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 56));
        assert(address(0xBEEF).balance == 0);
    }

    function test_approvedEscalationExecutesAndConsumesReservedNonce() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 57, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.approveEscalation(digest);
        fixture.hub.executeEscalated(digest);

        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.EXECUTED));
        assert(address(0xBEEF).balance == 2 ether);
        assert(MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 57));
        assert(
            MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 57) == bytes32(0)
        );
    }

    function test_pendingEscalationAndReservationSurviveModuleUpgrades() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 61, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);

        GrantlineEscalationManagerV2 managerImplementation = new GrantlineEscalationManagerV2();
        GrantlineEscalationRegistryV2 registryImplementation = new GrantlineEscalationRegistryV2();
        GrantlineEscalationExecutorV2 executorImplementation = new GrantlineEscalationExecutorV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](3);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(registryImplementation), version: 1, data: ""
        });
        upgrades[1] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.ESCALATION_MANAGER_MODULE(),
            implementation: address(managerImplementation),
            version: 1,
            data: ""
        });
        upgrades[2] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.EXECUTOR_MODULE(), implementation: address(executorImplementation), version: 1, data: ""
        });
        fixture.admin.upgradeModules(upgrades);

        assert(GrantlineEscalationManagerV2(fixture.hub.escalationManager()).marker() == 2);
        assert(GrantlineEscalationRegistryV2(fixture.hub.registry()).marker() == 2);
        assert(GrantlineEscalationExecutorV2(fixture.hub.executor()).marker() == 2);
        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.PENDING));
        assert(MandateRegistry(fixture.hub.registry()).reservedDigest(fixture.mandateId, fixture.agent, 61) == digest);

        fixture.hub.approveEscalation(digest);
        fixture.hub.executeEscalated(digest);
        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.EXECUTED));
        assert(MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 61));
    }

    function test_revocationBlocksApprovalButAllowsDenial() public {
        Fixture memory fixture = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 58, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        fixture.hub.revokeMandate(fixture.mandateId);

        fixtureVm.expectRevert();
        fixture.hub.approveEscalation(digest);
        fixture.hub.denyEscalation(digest);
        assert(fixture.hub.escalationStatus(digest) == uint8(EscalationManager.Status.DENIED));
    }

    function test_nonEscalatableDecisionAndDuplicateDigestAreRejected() public {
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory deniedPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 59, 0, _transferAction(address(0), address(0xBEEF), 3 ether)
        );
        bytes memory deniedSignature = _sign(fixture.hub, deniedPlan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert();
        fixture.hub.submitEscalation(deniedPlan, deniedSignature);

        Fixture memory escalating = _escalatingFixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            escalating.mandateId, escalating.agent, 60, 0, _transferAction(address(0), address(0xBEEF), 2 ether)
        );
        bytes memory signature = _sign(escalating.hub, plan, FIXTURE_AGENT_KEY);
        escalating.hub.submitEscalation(plan, signature);
        fixtureVm.expectRevert();
        escalating.hub.submitEscalation(plan, signature);
    }

    function test_unknownEscalationCannotBeReadOrExecuted() public {
        Fixture memory fixture = _fixture();
        bytes32 digest = keccak256("missing");
        fixtureVm.expectRevert(abi.encodeWithSelector(EscalationManager.EscalationNotFound.selector, digest));
        fixture.hub.getEscalation(digest);
        fixtureVm.expectRevert(abi.encodeWithSelector(EscalationManager.EscalationNotFound.selector, digest));
        fixture.hub.executeEscalated(digest);
    }

    function _escalatingFixture() private returns (Fixture memory) {
        return _fixtureWithRules(_rules(1 ether, true, 0, 0, false, true), _preflight(0, false), address(0), true);
    }
}
