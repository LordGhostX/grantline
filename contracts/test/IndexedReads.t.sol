// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {TestFixture} from "./TestFixture.sol";

contract IndexedReadsTest is TestFixture {
    function test_controllerVaultIndexFollowsReassignmentWithoutDuplicates() public {
        Fixture memory fixture = _fixture();
        address secondController = address(0xBEEF);
        fixtureVm.deal(secondController, 20 ether);

        fixtureVm.prank(secondController);
        address secondVault = fixture.hub.createVault();

        assert(fixture.hub.controllerVaultCount(fixture.controller) == 1);
        assert(fixture.hub.controllerVaultAt(fixture.controller, 0) == fixture.vault);
        assert(fixture.hub.controllerVaultCount(secondController) == 1);
        assert(fixture.hub.controllerVaultAt(secondController, 0) == secondVault);

        fixture.admin.setVaultController(fixture.vault, secondController);
        assert(fixture.hub.controllerVaultCount(fixture.controller) == 0);
        assert(fixture.hub.controllerVaultCount(secondController) == 2);
        assert(fixture.hub.controllerVaultAt(secondController, 0) == secondVault);
        assert(fixture.hub.controllerVaultAt(secondController, 1) == fixture.vault);

        fixture.admin.setVaultController(fixture.vault, secondController);
        assert(fixture.hub.controllerVaultCount(secondController) == 2);

        fixture.admin.setVaultController(fixture.vault, fixture.controller);
        assert(fixture.hub.controllerVaultCount(secondController) == 1);
        assert(fixture.hub.controllerVaultCount(fixture.controller) == 1);
        assert(fixture.hub.controllerVaultAt(fixture.controller, 0) == fixture.vault);
    }

    function test_mandateIndexesRecordVaultCreatorAndAgent() public {
        Fixture memory fixture = _fixture();
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);

        fixtureVm.prank(fixture.agent);
        uint256 childMandateId = fixture.hub
            .createChildMandate(
                fixture.mandateId, childAgent, _rules(1 ether, false, 0, false), _preflight(0, false, 0, false), 0, 0
            );

        MandateRegistry registry = MandateRegistry(fixture.hub.registry());
        GrantlineTypes.Mandate memory root = registry.getMandate(fixture.mandateId);
        GrantlineTypes.Mandate memory child = registry.getMandate(childMandateId);

        assert(root.createdBy == fixture.controller);
        assert(child.createdBy == fixture.agent);
        assert(registry.vaultMandateCount(fixture.vault) == 2);
        assert(registry.vaultMandateAt(fixture.vault, 0) == fixture.mandateId);
        assert(registry.vaultMandateAt(fixture.vault, 1) == childMandateId);
        assert(registry.creatorMandateCount(fixture.controller) == 1);
        assert(registry.creatorMandateAt(fixture.controller, 0) == fixture.mandateId);
        assert(registry.creatorMandateCount(fixture.agent) == 1);
        assert(registry.creatorMandateAt(fixture.agent, 0) == childMandateId);
        assert(registry.agentMandateCount(fixture.agent) == 1);
        assert(registry.agentMandateAt(fixture.agent, 0) == fixture.mandateId);
        assert(registry.agentMandateCount(childAgent) == 1);
        assert(registry.agentMandateAt(childAgent, 0) == childMandateId);
    }

    function test_escalationIndexesRetainTheFullHistory() public {
        Fixture memory fixture = _fixtureWithRules(_rules(1 ether, true, 0, true), _preflight(0, false, 0, false));
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 81, 0, _transferAction(address(0), address(0xCAFE), 2 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        EscalationManager manager = EscalationManager(fixture.hub.escalationManager());

        assert(manager.escalationCount() == 1);
        assert(manager.escalationAt(0) == digest);
        assert(manager.vaultEscalationCount(fixture.vault) == 1);
        assert(manager.vaultEscalationAt(fixture.vault, 0) == digest);
        assert(manager.agentEscalationCount(fixture.agent) == 1);
        assert(manager.agentEscalationAt(fixture.agent, 0) == digest);
        assert(manager.getEscalation(digest).submittedBy == address(this));

        fixture.hub.denyEscalation(digest);
        assert(manager.escalationCount() == 1);
        assert(manager.vaultEscalationCount(fixture.vault) == 1);
        assert(manager.agentEscalationCount(fixture.agent) == 1);
        assert(manager.getEscalation(digest).status == uint8(EscalationManager.Status.DENIED));
    }
}
