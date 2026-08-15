// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {ComponentTypes} from "../src/ComponentTypes.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {GrantlineOwnable2StepUpgradeable} from "../src/ProtocolAccess.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

interface GrantlineProtocolOwnership {
    function transferOwnership(address newOwner) external;

    function unpause() external;
}

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

contract GrantlineRegistryOwnershipV2 is MandateRegistry {
    function marker() external pure returns (uint256) {
        return 2;
    }

    function setOwnerForTest(address newOwner) external {
        _transferOwnership(newOwner);
    }

    function setPendingOwnerForTest(address newOwner) external {
        transferOwnership(newOwner);
    }
}

contract GrantlineEscalationRegistryV2 is EscalationManager {
    function setRegistryForTest(address registryAddress) external {
        registry = registryAddress;
    }
}

contract GrantlineExecutorRegistryV2 is VaultExecutor {
    function setRegistryForTest(address registryAddress) external {
        registry = registryAddress;
    }
}

contract GrantlineIncompletePauseVaultImplementation is UUPSUpgradeable {
    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.VAULT;
    }

    function paused() external pure returns (bool) {
        return false;
    }

    function _authorizeUpgrade(address) internal pure override {}
}

contract GrantlineReentrantVaultImplementation is UUPSUpgradeable {
    bool private _paused;

    function initialize(address grantlineAddress, address) external {
        Grantline(grantlineAddress).createVault();
    }

    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.VAULT;
    }

    function pauseInterfaceVersion() external pure returns (uint64) {
        return 1;
    }

    function pause() external {
        _paused = true;
    }

    function unpause() external {
        _paused = false;
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function _authorizeUpgrade(address) internal pure override {}
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

    function test_grantlineUpgradeRejectsWrongRoleImplementation() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                Grantline.InvalidComponentType.selector,
                "grantline.implementation",
                ComponentTypes.GRANTLINE,
                ComponentTypes.VAULT
            )
        );
        fixture.hub.upgradeToAndCall(address(implementation), "");
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

    function test_rejectsWrongRoleModuleImplementation() public {
        Fixture memory fixture = _fixture();
        VaultExecutor implementation = new VaultExecutor();
        Grantline.ModuleUpgrade[] memory upgrades = new Grantline.ModuleUpgrade[](1);
        upgrades[0] = Grantline.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(implementation), version: 1, data: ""
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                Grantline.InvalidComponentType.selector, "module", ComponentTypes.REGISTRY, ComponentTypes.EXECUTOR
            )
        );
        fixture.hub.upgradeModules(upgrades);

        assert(MandateRegistry(fixture.hub.registry()).componentType() == ComponentTypes.REGISTRY);
    }

    function test_rejectsWrongRoleVaultImplementations() public {
        Fixture memory fixture = _fixture();
        VaultExecutor implementation = new VaultExecutor();

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.hub.setVaultImplementation(address(implementation), 1);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.hub.upgradeVault(fixture.vault, address(implementation), 1, "");

        assert(fixture.hub.getVault(fixture.vault).implementation != address(implementation));
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).authority() == fixture.hub.executor());
    }

    function test_rejectsVaultImplementationWithoutPauseCapability() public {
        Fixture memory fixture = _fixture();
        GrantlineIncompletePauseVaultImplementation implementation = new GrantlineIncompletePauseVaultImplementation();
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.hub.setVaultImplementation(address(implementation), 1);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.hub.upgradeVault(fixture.vault, address(implementation), 1, "");

        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).authority() == fixture.hub.executor());
    }

    function test_moduleUpgradeRejectsExternalModuleOwner() public {
        Fixture memory fixture = _fixture();
        GrantlineRegistryOwnershipV2 implementation = new GrantlineRegistryOwnershipV2();
        address externalOwner = address(0xBEEF);
        Grantline.ModuleUpgrade[] memory upgrades = new Grantline.ModuleUpgrade[](1);
        upgrades[0] = Grantline.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineRegistryOwnershipV2.setOwnerForTest, (externalOwner))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                Grantline.InvalidModuleOwner.selector, ComponentTypes.REGISTRY, address(fixture.hub), externalOwner
            )
        );
        fixture.hub.upgradeModules(upgrades);

        assert(MandateRegistry(fixture.hub.registry()).owner() == address(fixture.hub));
        assert(MandateRegistry(fixture.hub.registry()).mandateCount() == 1);
        (bool markerPresent,) = fixture.hub.registry().call(abi.encodeCall(GrantlineRegistryOwnershipV2.marker, ()));
        assert(!markerPresent);
    }

    function test_moduleUpgradeRejectsPendingModuleOwner() public {
        Fixture memory fixture = _fixture();
        GrantlineRegistryOwnershipV2 implementation = new GrantlineRegistryOwnershipV2();
        address pendingOwner = address(0xCAFE);
        Grantline.ModuleUpgrade[] memory upgrades = new Grantline.ModuleUpgrade[](1);
        upgrades[0] = Grantline.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineRegistryOwnershipV2.setPendingOwnerForTest, (pendingOwner))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.InvalidModulePendingOwner.selector, ComponentTypes.REGISTRY, pendingOwner)
        );
        fixture.hub.upgradeModules(upgrades);

        assert(MandateRegistry(fixture.hub.registry()).owner() == address(fixture.hub));
        assert(MandateRegistry(fixture.hub.registry()).pendingOwner() == address(0));
    }

    function test_moduleUpgradeRejectsManagerRegistryMismatch() public {
        Fixture memory fixture = _fixture();
        GrantlineEscalationRegistryV2 implementation = new GrantlineEscalationRegistryV2();
        address alternateRegistry = address(new MandateRegistry());
        Grantline.ModuleUpgrade[] memory upgrades = new Grantline.ModuleUpgrade[](1);
        upgrades[0] = Grantline.ModuleUpgrade({
            key: fixture.hub.ESCALATION_MANAGER_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineEscalationRegistryV2.setRegistryForTest, (alternateRegistry))
        });

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidModuleRelationship.selector, "manager.registry"));
        fixture.hub.upgradeModules(upgrades);

        assert(EscalationManager(fixture.hub.escalationManager()).registry() == fixture.hub.registry());
    }

    function test_moduleUpgradeRejectsExecutorRegistryMismatch() public {
        Fixture memory fixture = _fixture();
        GrantlineExecutorRegistryV2 implementation = new GrantlineExecutorRegistryV2();
        address alternateRegistry = address(new MandateRegistry());
        Grantline.ModuleUpgrade[] memory upgrades = new Grantline.ModuleUpgrade[](1);
        upgrades[0] = Grantline.ModuleUpgrade({
            key: fixture.hub.EXECUTOR_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineExecutorRegistryV2.setRegistryForTest, (alternateRegistry))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.InvalidModuleRelationship.selector, "executor.registry")
        );
        fixture.hub.upgradeModules(upgrades);

        assert(VaultExecutor(fixture.hub.executor()).registry() == fixture.hub.registry());
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

    function test_createVaultRejectsReentrantVaultInitialization() public {
        Fixture memory fixture = _fixture();
        GrantlineReentrantVaultImplementation implementation = new GrantlineReentrantVaultImplementation();
        uint256 previousHubVaultCount = fixture.hub.vaultCount();
        uint256 previousFactoryVaultCount = VaultFactory(fixture.hub.vaultFactory()).vaultCount();

        fixture.hub.setVaultImplementation(address(implementation), 1);

        fixtureVm.expectRevert(abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        fixture.hub.createVault();

        assert(fixture.hub.vaultCount() == previousHubVaultCount);
        assert(VaultFactory(fixture.hub.vaultFactory()).vaultCount() == previousFactoryVaultCount);
        assert(fixture.hub.vaultAt(0) == fixture.vault);
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

    function test_existingVaultUpgradeRejectsPendingOwner() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();
        address pendingOwner = address(0xCAFE);
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;

        fixtureVm.expectRevert(
            abi.encodeWithSelector(Grantline.InvalidModuleRelationship.selector, "vault.pendingOwner")
        );
        fixture.hub
            .upgradeVault(
                fixture.vault,
                address(implementation),
                1,
                abi.encodeCall(GrantlineProtocolOwnership.transferOwnership, (pendingOwner))
            );

        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).pendingOwner() == address(0));
    }

    function test_existingVaultUpgradePreservesPauseState() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();

        fixture.hub.pauseVault(fixture.vault);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidModuleRelationship.selector, "vault.paused"));
        fixture.hub
            .upgradeVault(
                fixture.vault, address(implementation), 1, abi.encodeCall(GrantlineProtocolOwnership.unpause, ())
            );

        assert(Vault(payable(fixture.vault)).paused());
        assert(fixture.hub.getVault(fixture.vault).implementation != address(implementation));
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
