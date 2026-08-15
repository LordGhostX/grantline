// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {GrantlineOwnable2StepUpgradeable} from "../src/ProtocolAccess.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract GrantlineProtocolVaultV2 is Vault {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineProtocolRegistryV2 is MandateRegistry {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineProtocolEdgesTest is GrantlineTestFixture {
    function test_allImplementationInitializersAreDisabled() public {
        Grantline grantline = new Grantline();
        MandateRegistry registry = new MandateRegistry();
        MandateEvaluator evaluator = new MandateEvaluator();
        EscalationManager manager = new EscalationManager();
        VaultExecutor executor = new VaultExecutor();
        VaultFactory factory = new VaultFactory();
        Vault vault = new Vault();

        fixtureVm.expectRevert();
        grantline.initialize(address(this));
        fixtureVm.expectRevert();
        registry.initialize(address(this));
        fixtureVm.expectRevert();
        evaluator.initialize(address(this), address(this), address(0), true);
        fixtureVm.expectRevert();
        manager.initialize(address(this), address(this), address(this));
        fixtureVm.expectRevert();
        executor.initialize(address(this), address(this), address(this), address(this));
        fixtureVm.expectRevert();
        factory.initialize(address(this), address(vault), 1, address(this));
        fixtureVm.expectRevert();
        vault.initialize(address(this), address(this));
    }

    function test_ownershipRenunciationIsDisabled() public {
        Fixture memory fixture = _fixture();
        fixtureVm.expectRevert(
            abi.encodeWithSelector(GrantlineOwnable2StepUpgradeable.OwnershipRenunciationDisabled.selector)
        );
        fixture.hub.renounceOwnership();
        assert(fixture.hub.owner() == address(this));
    }

    function test_implementationInitializersAreDisabledAndHubConfiguresOnce() public {
        Grantline implementation = new Grantline();
        fixtureVm.expectRevert();
        implementation.initialize(address(this));

        Fixture memory fixture = _fixture();
        address registry = fixture.hub.registry();
        address evaluator = fixture.hub.evaluator();
        address escalationManager = fixture.hub.escalationManager();
        address executor = fixture.hub.executor();
        address vaultFactory = fixture.hub.vaultFactory();
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.AlreadyConfigured.selector));
        fixture.hub.configureModules(registry, evaluator, escalationManager, executor, vaultFactory);
    }

    function test_ownershipTransferRequiresPendingOwnerAcceptance() public {
        Fixture memory fixture = _fixture();
        address nextAdmin = address(0xCAFE);
        fixture.hub.transferOwnership(nextAdmin);
        assert(fixture.hub.owner() == address(this));
        assert(fixture.hub.pendingOwner() == nextAdmin);

        fixtureVm.prank(nextAdmin);
        fixture.hub.acceptOwnership();
        assert(fixture.hub.owner() == nextAdmin);
        assert(fixture.hub.pendingOwner() == address(0));
    }

    function test_rejectsUnknownVaultsZeroControllersAndInvalidImplementations() public {
        Fixture memory fixture = _fixture();

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.VaultNotRegistered.selector, address(0xCAFE)));
        fixture.hub.getVault(address(0xCAFE));

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.VaultNotRegistered.selector, address(0xCAFE)));
        fixture.hub.setVaultController(address(0xCAFE), address(0xBEEF));

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidController.selector));
        fixture.hub.setVaultController(fixture.vault, address(0));

        fixtureVm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(0)));
        fixture.hub.setVaultImplementation(address(0), 1);
    }

    function test_factoryTemplateOnlyAffectsFutureVaults() public {
        Fixture memory fixture = _fixture();
        address existingVault = fixture.vault;
        address secondVault = fixture.hub.createVault();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();

        fixture.hub.setVaultImplementation(address(implementation), 1);
        address futureVault = fixture.hub.createVault();

        assert(fixture.hub.getVault(existingVault).implementation != address(implementation));
        assert(fixture.hub.getVault(secondVault).implementation != address(implementation));
        assert(fixture.hub.getVault(futureVault).implementation == address(implementation));
        assert(fixture.hub.vaultCount() == 3);
        assert(fixture.hub.vaultAt(0) == existingVault);
        assert(fixture.hub.vaultAt(2) == futureVault);

        fixtureVm.expectRevert();
        fixture.hub.vaultAt(3);
    }

    function test_existingVaultUpgradePreservesStateAndChecksVersion() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;

        fixtureVm.expectRevert();
        fixture.hub.upgradeVault(fixture.vault, address(implementation), 2, "");
        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);

        fixture.hub.upgradeVault(fixture.vault, address(implementation), 1, "");
        assert(GrantlineProtocolVaultV2(payable(fixture.vault)).marker() == 2);
        assert(fixture.hub.getVault(fixture.vault).implementation == address(implementation));
    }

    function test_moduleUpgradeIsAtomicAndPreservesRegistryStorage() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolRegistryV2 implementation = new GrantlineProtocolRegistryV2();
        Grantline.ModuleUpgrade[] memory upgrades = new Grantline.ModuleUpgrade[](1);
        upgrades[0] = Grantline.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(implementation), version: 2, data: ""
        });

        fixtureVm.expectRevert();
        fixture.hub.upgradeModules(upgrades);
        (bool markerPresent,) = fixture.hub.registry().call(abi.encodeCall(GrantlineProtocolRegistryV2.marker, ()));
        assert(!markerPresent);

        upgrades[0].version = 1;
        fixture.hub.upgradeModules(upgrades);
        assert(GrantlineProtocolRegistryV2(fixture.hub.registry()).marker() == 2);
        assert(MandateRegistry(fixture.hub.registry()).mandateCount() == 1);
        assert(MandateRegistry(fixture.hub.registry()).isRegisteredVault(fixture.vault));
    }

    function test_controllerReassignmentChangesOnlyControllerAuthority() public {
        Fixture memory fixture = _fixture();
        address nextController = address(0xCAFE);
        fixture.hub.setVaultController(fixture.vault, nextController);
        assert(fixture.hub.controllerOf(fixture.vault) == nextController);
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).authority() == fixture.hub.executor());

        fixtureVm.expectRevert();
        fixture.hub.depositNative{value: 0}(fixture.vault);
    }
}
