// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract GrantlineRegistryEdgesTest is GrantlineTestFixture {
    function test_rejectsInvalidMandateAddressesAndRanges() public {
        Fixture memory fixture = _fixture();
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.InvalidAddress.selector));
        fixture.hub.createMandate(fixture.vault, address(0), rules, _preflight(0, false), 0, 0);

        rules.minNativeAmount = 2 ether;
        rules.maxNativeAmount = 1 ether;
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.InvalidNativeAmountRange.selector, 2 ether, 1 ether)
        );
        fixture.hub.createMandate(fixture.vault, fixture.agent, rules, _preflight(0, false), 0, 0);
    }

    function test_childRulesAndPreflightRulesOnlyNarrowAuthority() public {
        GrantlineTypes.MandateRules memory parentRules = _rules(5 ether, true, 1 ether, true);
        Fixture memory fixture = _fixtureWithRules(parentRules, _preflight(1 ether, true));

        GrantlineTypes.MandateRules memory childRules = _rules(4 ether, true, 2 ether, true);
        fixtureVm.prank(fixture.agent);
        uint256 childId = fixture.hub
            .createChildMandate(
                fixture.mandateId, fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY), childRules, _preflight(2 ether, true), 0, 0
            );

        GrantlineTypes.MandateRules memory effectiveRules = fixture.hub.getEffectiveRules(childId);
        GrantlineTypes.PreflightRules memory effectivePreflight = fixture.hub.getEffectivePreflightRules(childId);
        assert(effectiveRules.minNativeAmount == 2 ether);
        assert(effectiveRules.maxNativeAmount == 4 ether);
        assert(effectiveRules.canDelegate);
        assert(effectivePreflight.minNativeBalance == 2 ether);
        assert(effectivePreflight.escalateNativeBalance);

        GrantlineTypes.MandateRules memory grandchildRules = _rules(3 ether, true, 3 ether, false);
        fixtureVm.prank(fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY));
        uint256 grandchildId = fixture.hub
            .createChildMandate(childId, fixtureVm.addr(0xCAFE), grandchildRules, _preflight(3 ether, true), 0, 0);

        GrantlineTypes.MandateView memory grandchild = fixture.hub.getMandate(grandchildId);
        assert(grandchild.delegationDepth == 2);
        assert(!grandchild.rules.canDelegate);

        grandchildRules.canDelegate = true;
        fixtureVm.prank(fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY));
        fixture.hub.updateMandate(grandchildId, grandchildRules, _preflight(3 ether, true), 0, 0);
        assert(!fixture.hub.getMandate(grandchildId).rules.canDelegate);
    }

    function test_rejectsBroaderChildRulesAndPreflightRules() public {
        GrantlineTypes.MandateRules memory parentRules = _rules(4 ether, false, 2 ether, true);
        Fixture memory fixture = _fixtureWithRules(parentRules, _preflight(2 ether, false));
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);

        GrantlineTypes.MandateRules memory broadRules = _rules(4 ether, false, 1 ether, true);
        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.ChildRulesExceedParent.selector, fixture.mandateId)
        );
        fixture.hub.createChildMandate(fixture.mandateId, childAgent, broadRules, _preflight(2 ether, false), 0, 0);

        GrantlineTypes.MandateRules memory validRules = _rules(4 ether, false, 2 ether, true);
        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.ChildPreflightRulesExceedParent.selector, fixture.mandateId)
        );
        fixture.hub.createChildMandate(fixture.mandateId, childAgent, validRules, _preflight(1 ether, false), 0, 0);
    }

    function test_delegationRequiresTheParentAgentAndActiveLineage() public {
        Fixture memory fixture = _fixture();
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        GrantlineTypes.MandateRules memory childRules = _rules(1 ether, false, 0, false);

        fixtureVm.prank(address(0xCAFE));
        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.NotParentAgent.selector, fixture.mandateId, address(0xCAFE))
        );
        fixture.hub.createChildMandate(fixture.mandateId, childAgent, childRules, _preflight(0, false), 0, 0);

        fixture.hub.revokeMandate(fixture.mandateId);
        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.NotParentAgent.selector, fixture.mandateId, fixture.agent)
        );
        fixture.hub.createChildMandate(fixture.mandateId, childAgent, childRules, _preflight(0, false), 0, 0);
    }

    function test_revokePreservesHistoryButBlocksFutureAdministration() public {
        Fixture memory fixture = _fixture();
        fixture.hub.revokeMandate(fixture.mandateId);

        GrantlineTypes.MandateView memory revoked = fixture.hub.getMandate(fixture.mandateId);
        assert(revoked.status == GrantlineTypes.MandateStatus.REVOKED);
        assert(revoked.revokedAt != 0);
        assert(!fixture.hub.isController(fixture.vault, fixture.agent));

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotActive.selector, fixture.mandateId));
        fixture.hub.revokeMandate(fixture.mandateId);
    }

    function test_pauseMandateIsInheritedWithoutCascadingState() public {
        Fixture memory fixture = _fixture();
        address childAgent = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        uint256 childId;
        fixtureVm.prank(fixture.agent);
        childId = fixture.hub
            .createChildMandate(
                fixture.mandateId, childAgent, _rules(1 ether, false, 0, false), _preflight(0, false), 0, 0
            );

        fixture.hub.pauseMandate(fixture.mandateId);
        assert(fixture.hub.getMandate(fixture.mandateId).status == GrantlineTypes.MandateStatus.PAUSED);
        assert(!MandateRegistry(fixture.hub.registry()).isActive(fixture.mandateId));
        assert(!MandateRegistry(fixture.hub.registry()).isActive(0));
        assert(fixture.hub.getMandate(childId).status == GrantlineTypes.MandateStatus.ACTIVE);
        assert(MandateRegistry(fixture.hub.registry()).isLineagePaused(childId));
        assert(!MandateRegistry(fixture.hub.registry()).isLineageActive(childId));

        fixture.hub.unpauseMandate(fixture.mandateId);
        assert(MandateRegistry(fixture.hub.registry()).isActive(fixture.mandateId));
        assert(MandateRegistry(fixture.hub.registry()).isLineageActive(childId));

        fixtureVm.prank(fixture.agent);
        fixture.hub.pauseMandate(childId);
        fixture.hub.unpauseMandate(childId);
        assert(fixture.hub.getMandate(childId).status == GrantlineTypes.MandateStatus.ACTIVE);

        fixture.hub.pauseMandate(childId);
        fixture.hub.updateMandate(childId, _rules(0.5 ether, false, 0, false), _preflight(0, false), 0, 0);
        fixture.hub.revokeMandate(childId);
        assert(fixture.hub.getMandate(childId).status == GrantlineTypes.MandateStatus.REVOKED);
    }

    function test_pausedMandateRejectsInvalidTransitionsAndChildCreation() public {
        Fixture memory fixture = _fixture();
        fixture.hub.pauseMandate(fixture.mandateId);

        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotActive.selector, fixture.mandateId));
        fixture.hub.pauseMandate(fixture.mandateId);

        fixtureVm.prank(fixture.agent);
        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.NotParentAgent.selector, fixture.mandateId, fixture.agent)
        );
        fixture.hub
            .createChildMandate(
                fixture.mandateId,
                fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY),
                _rules(1 ether, false, 0, false),
                _preflight(0, false),
                0,
                0
            );

        fixture.hub.unpauseMandate(fixture.mandateId);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotPaused.selector, fixture.mandateId));
        fixture.hub.unpauseMandate(fixture.mandateId);

        fixture.hub.revokeMandate(fixture.mandateId);
        fixtureVm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotPaused.selector, fixture.mandateId));
        fixture.hub.unpauseMandate(fixture.mandateId);
    }
}
