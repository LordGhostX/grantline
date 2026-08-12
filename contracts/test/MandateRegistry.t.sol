// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";

interface RegistryTestVm {
    function prank(address sender) external;
}

contract RegistryAuthorityStub {
    address public immutable escalationManager;

    constructor(address manager) {
        escalationManager = manager;
    }

    function consumeNonce(
        MandateRegistry registry,
        uint256 mandateId,
        address agent,
        uint256 nonce
    ) external {
        registry.consumeNonce(mandateId, agent, nonce);
    }

    function consumeReservedNonce(
        MandateRegistry registry,
        uint256 mandateId,
        address agent,
        uint256 nonce,
        bytes32 digest
    ) external {
        registry.consumeReservedNonce(mandateId, agent, nonce, digest);
    }
}

contract MandateRegistryTest {
    RegistryTestVm private constant vm =
        RegistryTestVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_createsActiveMandateForVaultOwner() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address agent = address(0xA11CE);

        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(10 ether, 1_000e18)
        );
        MandateRegistry.Mandate memory mandate = registry.getMandate(mandateId);

        assert(mandateId == 1);
        assert(registry.mandateCount() == 1);
        assert(mandate.id == 1);
        assert(mandate.owner == address(this));
        assert(mandate.vault == address(vault));
        assert(mandate.agent == agent);
        assert(mandate.status == MandateRegistry.MandateStatus.ACTIVE);
        assert(mandate.rules.maxNativeAmount == 10 ether);
        assert(mandate.rules.maxUsdAmount == 1_000e18);
        assert(registry.isActive(mandateId));
    }

    function test_rejectsInvalidCreationInputs() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        bool zeroAddressReverted;
        bool zeroTransactionLimitAllowed;
        bool unknownVaultReverted;

        try
            registry.createMandate(
                address(0),
                address(0xA11CE),
                _rules(1 ether, 0)
            )
        {} catch {
            zeroAddressReverted = true;
        }
        try
            registry.createMandate(
                address(vault),
                address(0xA11CE),
                _rules(0, 0)
            )
        {
            zeroTransactionLimitAllowed = true;
        } catch {}
        try
            registry.createMandate(
                address(0xBEEF),
                address(0xA11CE),
                _rules(1 ether, 0)
            )
        {} catch {
            unknownVaultReverted = true;
        }

        assert(zeroAddressReverted);
        assert(zeroTransactionLimitAllowed);
        assert(unknownVaultReverted);
        assert(registry.mandateCount() == 1);
    }

    function test_rejectsCreationByNonVaultOwner() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        bool reverted;

        vm.prank(address(0xB0B));
        try
            registry.createMandate(
                address(vault),
                address(0xA11CE),
                _rules(1 ether, 0)
            )
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(registry.mandateCount() == 0);
    }

    function test_currentVaultOwnerCanUpdateMandate() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            address(0xA11CE),
            _rules(10 ether, 1_000e18)
        );

        registry.updateMandate(mandateId, _rules(20 ether, 2_000e18));
        MandateRegistry.Mandate memory mandate = registry.getMandate(mandateId);

        assert(mandate.rules.maxNativeAmount == 20 ether);
        assert(mandate.rules.maxUsdAmount == 2_000e18);
        assert(mandate.status == MandateRegistry.MandateStatus.ACTIVE);

        registry.updateMandate(mandateId, _rules(0, 0));
        assert(registry.getMandate(mandateId).rules.maxNativeAmount == 0);
        assert(registry.getMandate(mandateId).rules.maxUsdAmount == 0);
    }

    function test_consumesNonceOnlyOnceForCurrentVaultAuthority() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address agent = address(0xA11CE);
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(0, 0)
        );
        vault.setAuthority(address(this));

        registry.consumeNonce(mandateId, agent, 7);
        assert(registry.nonceUsed(mandateId, agent, 7));

        bool duplicateReverted;
        try registry.consumeNonce(mandateId, agent, 7) {} catch {
            duplicateReverted = true;
        }

        assert(duplicateReverted);
    }

    function test_rejectsNonceConsumptionFromNonAuthorityOrWrongAgent() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address agent = address(0xA11CE);
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(0, 0)
        );
        vault.setAuthority(address(this));

        bool wrongAgentReverted;
        bool nonAuthorityReverted;
        try registry.consumeNonce(mandateId, address(0xB0B), 1) {} catch {
            wrongAgentReverted = true;
        }
        vm.prank(address(0xB0B));
        try registry.consumeNonce(mandateId, agent, 1) {} catch {
            nonAuthorityReverted = true;
        }

        assert(wrongAgentReverted);
        assert(nonAuthorityReverted);
        assert(!registry.nonceUsed(mandateId, agent, 1));
    }

    function test_reservationSurvivesAuthorityReplacementAndRequiresDigest()
        public
    {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address agent = address(0xA11CE);
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(0, 0)
        );
        RegistryAuthorityStub firstAuthority = new RegistryAuthorityStub(
            address(this)
        );
        vault.setAuthority(address(firstAuthority));
        bytes32 digest = keccak256("reserved-plan");

        registry.reserveNonce(mandateId, agent, 7, digest);

        bool normalConsumptionReverted;
        try
            firstAuthority.consumeNonce(registry, mandateId, agent, 7)
        {} catch {
            normalConsumptionReverted = true;
        }
        assert(normalConsumptionReverted);
        assert(registry.reservedDigest(mandateId, agent, 7) == digest);
        assert(!registry.nonceUsed(mandateId, agent, 7));

        RegistryAuthorityStub replacementAuthority = new RegistryAuthorityStub(
            address(0xB0B)
        );
        vault.setAuthority(address(replacementAuthority));

        bool formerManagerReverted;
        try
            registry.reserveNonce(
                mandateId,
                agent,
                8,
                keccak256("stale-manager-plan")
            )
        {} catch {
            formerManagerReverted = true;
        }
        bool wrongDigestReverted;
        try
            replacementAuthority.consumeReservedNonce(
                registry,
                mandateId,
                agent,
                7,
                keccak256("different-plan")
            )
        {} catch {
            wrongDigestReverted = true;
        }

        assert(formerManagerReverted);
        assert(wrongDigestReverted);
        assert(registry.reservedDigest(mandateId, agent, 7) == digest);
        assert(!registry.nonceUsed(mandateId, agent, 7));

        replacementAuthority.consumeReservedNonce(
            registry,
            mandateId,
            agent,
            7,
            digest
        );
        assert(registry.reservedDigest(mandateId, agent, 7) == bytes32(0));
        assert(registry.nonceUsed(mandateId, agent, 7));
    }

    function test_vaultOwnershipTransferMovesMandateAdministration() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address newOwner = address(0xCAFE);
        uint256 mandateId = registry.createMandate(
            address(vault),
            address(0xA11CE),
            _rules(10 ether, 1_000e18)
        );
        vault.transferOwnership(newOwner);

        vm.prank(newOwner);
        registry.updateMandate(mandateId, _rules(20 ether, 2_000e18));

        bool formerOwnerReverted;
        try
            registry.updateMandate(mandateId, _rules(30 ether, 3_000e18))
        {} catch {
            formerOwnerReverted = true;
        }

        assert(formerOwnerReverted);
        assert(
            registry.getMandate(mandateId).rules.maxNativeAmount == 20 ether
        );
        assert(registry.getMandate(mandateId).rules.maxUsdAmount == 2_000e18);
    }

    function test_revokesWithoutDeletingHistory() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address agent = address(0xA11CE);
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(10 ether, 1_000e18)
        );

        registry.revokeMandate(mandateId);
        MandateRegistry.Mandate memory mandate = registry.getMandate(mandateId);

        assert(!registry.isActive(mandateId));
        assert(mandate.id == mandateId);
        assert(mandate.agent == agent);
        assert(mandate.status == MandateRegistry.MandateStatus.REVOKED);
        assert(mandate.revokedAt > 0);
    }

    function test_rejectsUpdatesAndDoubleRevocationAfterRevoke() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            address(0xA11CE),
            _rules(10 ether, 1_000e18)
        );
        registry.revokeMandate(mandateId);
        bool updateReverted;
        bool revokeReverted;

        try
            registry.updateMandate(mandateId, _rules(20 ether, 2_000e18))
        {} catch {
            updateReverted = true;
        }
        try registry.revokeMandate(mandateId) {} catch {
            revokeReverted = true;
        }

        assert(updateReverted);
        assert(revokeReverted);
    }

    function test_idsAreMonotonicAndNeverReused() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 firstId = registry.createMandate(
            address(vault),
            address(0xA11CE),
            _rules(10 ether, 1_000e18)
        );
        registry.revokeMandate(firstId);
        uint256 secondId = registry.createMandate(
            address(vault),
            address(0xB0B),
            _rules(5 ether, 500e18)
        );

        assert(firstId == 1);
        assert(secondId == 2);
        assert(registry.mandateCount() == 2);
        assert(!registry.isActive(firstId));
        assert(registry.isActive(secondId));
    }

    function test_unknownMandateQueriesAreSafe() public {
        MandateRegistry registry = new MandateRegistry();
        bool getReverted;

        try registry.getMandate(1) {} catch {
            getReverted = true;
        }

        assert(getReverted);
        assert(!registry.isActive(1));
    }

    function test_createsNestedDelegationAndComputesEffectiveRules() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address treasuryAgent = address(0xA11CE);
        address executionAgent = address(0xB0B);
        address paymentAgent = address(0xCAFE);

        uint256 rootId = registry.createMandate(
            address(vault),
            treasuryAgent,
            _delegatableRules(10 ether, 1_000e18)
        );

        vm.prank(treasuryAgent);
        uint256 childId = registry.createChildMandate(
            rootId,
            executionAgent,
            _delegatableRules(8 ether, 800e18)
        );

        vm.prank(executionAgent);
        uint256 grandchildId = registry.createChildMandate(
            childId,
            paymentAgent,
            _rules(5 ether, 500e18)
        );

        MandateRegistry.Mandate memory child = registry.getMandate(childId);
        MandateRegistry.Mandate memory grandchild = registry.getMandate(
            grandchildId
        );
        uint256[] memory lineage = registry.getLineage(grandchildId);
        MandateRegistry.MandateRules memory effective = registry
            .getEffectiveRules(grandchildId);

        assert(child.parentMandateId == rootId);
        assert(child.delegationDepth == 1);
        assert(grandchild.parentMandateId == childId);
        assert(grandchild.delegationDepth == 2);
        assert(lineage.length == 3);
        assert(lineage[0] == rootId);
        assert(lineage[1] == childId);
        assert(lineage[2] == grandchildId);
        assert(effective.minNativeAmount == 0);
        assert(effective.maxNativeAmount == 5 ether);
        assert(effective.maxUsdAmount == 500e18);
        assert(!effective.canDelegate);
        assert(registry.isLineageActive(grandchildId));
    }

    function test_parentTighteningChangesChildEffectiveRules() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address parentAgent = address(0xA11CE);
        uint256 rootId = registry.createMandate(
            address(vault),
            parentAgent,
            _delegatableRules(10 ether, 1_000e18)
        );

        vm.prank(parentAgent);
        uint256 childId = registry.createChildMandate(
            rootId,
            address(0xB0B),
            _rules(8 ether, 800e18)
        );

        assert(registry.getEffectiveRules(childId).maxNativeAmount == 8 ether);

        registry.updateMandate(rootId, _delegatableRules(5 ether, 500e18));
        assert(registry.getEffectiveRules(childId).maxNativeAmount == 5 ether);

        registry.updateMandate(rootId, _delegatableRules(9 ether, 900e18));
        assert(registry.getEffectiveRules(childId).maxNativeAmount == 8 ether);

        registry.updateMandate(rootId, _rules(9 ether, 900e18));
        assert(!registry.getEffectiveRules(childId).canDelegate);
    }

    function test_capsDelegationDepthAndRejectsDelegatableGrandchild() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address rootAgent = address(0xA11CE);
        address childAgent = address(0xB0B);
        address grandchildAgent = address(0xCAFE);
        uint256 rootId = registry.createMandate(
            address(vault),
            rootAgent,
            _delegatableRules(10 ether, 0)
        );

        vm.prank(rootAgent);
        uint256 childId = registry.createChildMandate(
            rootId,
            childAgent,
            _delegatableRules(8 ether, 0)
        );

        bool grandchildReverted;
        vm.prank(childAgent);
        try
            registry.createChildMandate(
                childId,
                grandchildAgent,
                _delegatableRules(5 ether, 0)
            )
        {} catch {
            grandchildReverted = true;
        }
        assert(grandchildReverted);
    }

    function test_forcesDepthTwoUpdatesToRemainNonDelegatable() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address rootAgent = address(0xA11CE);
        address childAgent = address(0xB0B);
        address grandchildAgent = address(0xCAFE);
        uint256 rootId = registry.createMandate(
            address(vault),
            rootAgent,
            _delegatableRules(10 ether, 0)
        );

        vm.prank(rootAgent);
        uint256 childId = registry.createChildMandate(
            rootId,
            childAgent,
            _delegatableRules(8 ether, 0)
        );
        vm.prank(childAgent);
        uint256 grandchildId = registry.createChildMandate(
            childId,
            grandchildAgent,
            _rules(5 ether, 0)
        );

        registry.updateMandate(
            grandchildId,
            MandateRegistry.MandateRules({
                canDelegate: true,
                minNativeAmount: 0,
                maxNativeAmount: 4 ether,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false
            })
        );

        MandateRegistry.Mandate memory grandchild = registry.getMandate(
            grandchildId
        );
        assert(!grandchild.rules.canDelegate);
        assert(!registry.getEffectiveRules(grandchildId).canDelegate);

        bool childCreationReverted;
        vm.prank(grandchildAgent);
        try
            registry.createChildMandate(
                grandchildId,
                address(0xD00D),
                _rules(3 ether, 0)
            )
        {} catch {
            childCreationReverted = true;
        }
        assert(childCreationReverted);
    }

    function test_parentAndOwnerCanAdministerChildWithinInheritance() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address parentAgent = address(0xA11CE);
        uint256 rootId = registry.createMandate(
            address(vault),
            parentAgent,
            _delegatableRules(10 ether, 1_000e18)
        );

        vm.prank(parentAgent);
        uint256 childId = registry.createChildMandate(
            rootId,
            address(0xB0B),
            _rules(8 ether, 800e18)
        );

        vm.prank(parentAgent);
        registry.updateMandate(childId, _rules(7 ether, 700e18));
        assert(registry.getMandate(childId).rules.maxNativeAmount == 7 ether);

        registry.updateMandate(childId, _rules(6 ether, 600e18));
        assert(registry.getMandate(childId).rules.maxNativeAmount == 6 ether);

        bool childAgentReverted;
        vm.prank(address(0xB0B));
        try registry.updateMandate(childId, _rules(5 ether, 500e18)) {} catch {
            childAgentReverted = true;
        }
        assert(childAgentReverted);

        vm.prank(parentAgent);
        registry.revokeMandate(childId);
        assert(
            registry.getMandate(childId).status ==
                MandateRegistry.MandateStatus.REVOKED
        );
    }

    function test_rejectsInvalidDelegationAndBroaderChildRules() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address parentAgent = address(0xA11CE);
        uint256 rootId = registry.createMandate(
            address(vault),
            parentAgent,
            _rules(10 ether, 1_000e18)
        );

        bool disabledReverted;
        vm.prank(parentAgent);
        try
            registry.createChildMandate(
                rootId,
                address(0xB0B),
                _rules(5 ether, 500e18)
            )
        {} catch {
            disabledReverted = true;
        }
        assert(disabledReverted);

        uint256 delegatableRootId = registry.createMandate(
            address(vault),
            parentAgent,
            _delegatableRules(10 ether, 1_000e18)
        );
        bool callerReverted;
        vm.prank(address(0xD00D));
        try
            registry.createChildMandate(
                delegatableRootId,
                address(0xB0B),
                _rules(5 ether, 500e18)
            )
        {} catch {
            callerReverted = true;
        }
        assert(callerReverted);

        bool broaderReverted;
        vm.prank(parentAgent);
        try
            registry.createChildMandate(
                delegatableRootId,
                address(0xCAFE),
                _rules(11 ether, 1_000e18)
            )
        {} catch {
            broaderReverted = true;
        }
        assert(broaderReverted);
    }

    function test_revokedParentInvalidatesDescendantsButOwnerCanCloseThem()
        public
    {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        address parentAgent = address(0xA11CE);
        uint256 rootId = registry.createMandate(
            address(vault),
            parentAgent,
            _delegatableRules(10 ether, 1_000e18)
        );

        vm.prank(parentAgent);
        uint256 childId = registry.createChildMandate(
            rootId,
            address(0xB0B),
            _rules(5 ether, 500e18)
        );

        registry.revokeMandate(rootId);
        assert(!registry.isLineageActive(childId));

        bool effectiveRulesReverted;
        try registry.getEffectiveRules(childId) {} catch {
            effectiveRulesReverted = true;
        }
        assert(effectiveRulesReverted);

        bool parentUpdateReverted;
        vm.prank(parentAgent);
        try registry.updateMandate(childId, _rules(4 ether, 400e18)) {} catch {
            parentUpdateReverted = true;
        }
        assert(parentUpdateReverted);

        registry.revokeMandate(childId);
        assert(
            registry.getMandate(childId).status ==
                MandateRegistry.MandateStatus.REVOKED
        );
    }

    function test_rejectsInvalidAmountRanges() public {
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        bool nativeReverted;
        bool usdReverted;

        try
            registry.createMandate(
                address(vault),
                address(0xA11CE),
                MandateRegistry.MandateRules({
                    minNativeAmount: 2 ether,
                    maxNativeAmount: 1 ether,
                    escalateNativeAmount: false,
                    minUsdAmount: 0,
                    maxUsdAmount: 0,
                    escalateUsdAmount: false,
                    canDelegate: false
                })
            )
        {} catch {
            nativeReverted = true;
        }
        try
            registry.createMandate(
                address(vault),
                address(0xA11CE),
                MandateRegistry.MandateRules({
                    minNativeAmount: 0,
                    maxNativeAmount: 0,
                    escalateNativeAmount: false,
                    minUsdAmount: 2_000e18,
                    maxUsdAmount: 1_000e18,
                    escalateUsdAmount: false,
                    canDelegate: false
                })
            )
        {} catch {
            usdReverted = true;
        }

        assert(nativeReverted);
        assert(usdReverted);
        assert(registry.mandateCount() == 0);
    }

    function _rules(
        uint256 maxNativeAmount,
        uint256 maxUsdAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: maxUsdAmount,
                escalateUsdAmount: false,
                canDelegate: false
            });
    }

    function _delegatableRules(
        uint256 maxNativeAmount,
        uint256 maxUsdAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: maxUsdAmount,
                escalateUsdAmount: false,
                canDelegate: true
            });
    }
}
