// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";

interface RegistryTestVm {
    function prank(address sender) external;
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
                    escalateUsdAmount: false
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
                    escalateUsdAmount: false
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
                escalateUsdAmount: false
            });
    }
}
