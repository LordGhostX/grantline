// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {ComponentTypes} from "../src/ComponentTypes.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {GrantlineOwnable2StepUpgradeable} from "../src/ProtocolAccess.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TestFixture} from "./TestFixture.sol";

interface GrantlineProtocolOwnership {
    function transferOwnership(address newOwner) external;

    function unpause() external;
}

contract GrantlineSwapConfigMock {
    address public immutable grantline;

    constructor(address grantlineAddress) {
        grantline = grantlineAddress;
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.SWAP_ADAPTER;
    }

    function swapAdapterId() external pure returns (ActionTypes.SwapAdapterId) {
        return ActionTypes.SwapAdapterId.UNISWAP_V3;
    }
}

contract GrantlineNoopAdmin {
    address public immutable grantline;

    constructor(address grantlineAddress) {
        grantline = grantlineAddress;
    }

    function acceptModules() external pure returns (bool) {
        return true;
    }
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

    function initialize(address grantlineAddress, address, address) external {
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

contract GrantlineWrongUpgradeAuthorityVaultImplementation is Vault {
    function initialize(address grantlineAddress, address authorityAddress, address) external override initializer {
        if (grantlineAddress == address(0) || authorityAddress == address(0) || authorityAddress.code.length == 0) {
            revert InvalidAddress();
        }
        grantline = grantlineAddress;
        authority = authorityAddress;
        upgradeAuthority = address(0xBEEF);
        __Ownable_init(grantlineAddress);
        __Ownable2Step_init();
        __Pausable_init();
    }
}

contract GrantlineWrongUuidVaultImplementation {
    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(0);
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.VAULT;
    }

    function pauseInterfaceVersion() external pure returns (uint64) {
        return 1;
    }

    function paused() external pure returns (bool) {
        return false;
    }

    function pause() external {}

    function unpause() external {}

    function version() external pure returns (uint64) {
        return 1;
    }
}

contract GrantlineMissingUnpauseVaultImplementation is UUPSUpgradeable {
    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.VAULT;
    }

    function pauseInterfaceVersion() external pure returns (uint64) {
        return 1;
    }

    function paused() external pure returns (bool) {
        return false;
    }

    function pause() external {}

    function _authorizeUpgrade(address) internal pure override {}
}

abstract contract GrantlineIncompleteSwapVaultImplementation is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    address public authority;
    address public upgradeAuthority;

    function initialize(address grantlineAddress, address authorityAddress, address upgradeAuthorityAddress)
        external
        initializer
    {
        if (
            grantlineAddress == address(0) || authorityAddress == address(0) || authorityAddress.code.length == 0
                || upgradeAuthorityAddress == address(0) || upgradeAuthorityAddress.code.length == 0
        ) revert();
        authority = authorityAddress;
        upgradeAuthority = upgradeAuthorityAddress;
        __Ownable_init(grantlineAddress);
        __Ownable2Step_init();
        __Pausable_init();
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != upgradeAuthority) revert();
    }
}

contract GrantlineMissingExecuteSwapVaultImplementation is GrantlineIncompleteSwapVaultImplementation {
    function receiveNativeFromSwapAdapter(address) external payable {}
}

contract GrantlineMissingSwapNativeReceiverVaultImplementation is GrantlineIncompleteSwapVaultImplementation {
    function executeSwap(address, ActionTypes.SwapParameters calldata) external pure returns (uint256) {
        return 0;
    }
}

contract GrantlinePausedVaultImplementation is UUPSUpgradeable {
    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.VAULT;
    }

    function pauseInterfaceVersion() external pure returns (uint64) {
        return 1;
    }

    function paused() external pure returns (bool) {
        return true;
    }

    function pause() external {}

    function unpause() external {}

    function _authorizeUpgrade(address) internal pure override {}
}

contract GrantlineProtocolVaultFactoryV2 is VaultFactory {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract ProtocolEdgesTest is TestFixture {
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
        registry.initialize(address(this), address(this));
        fixtureVm.expectRevert();
        evaluator.initialize(address(this), address(this), address(0), 0, address(0), address(this));
        fixtureVm.expectRevert();
        manager.initialize(address(this), address(this), address(this), address(this));
        fixtureVm.expectRevert();
        executor.initialize(address(this), address(this), address(this), address(this), address(this));
        fixtureVm.expectRevert();
        factory.initialize(address(this), address(vault), 1, address(this), address(this), address(this));
        fixtureVm.expectRevert();
        vault.initialize(address(this), address(this), address(this));
    }

    function test_grantlineProxyInitializationRejectsZeroOwner() public {
        Grantline implementation = new Grantline();
        _expectProxyInitializationRevert(address(implementation), abi.encodeCall(Grantline.initialize, (address(0))));
    }

    function test_registryProxyInitializationRejectsZeroGrantline() public {
        MandateRegistry implementation = new MandateRegistry();
        _expectProxyInitializationRevert(
            address(implementation), abi.encodeCall(MandateRegistry.initialize, (address(0), address(this)))
        );
    }

    function test_evaluatorProxyInitializationRejectsZeroRegistry() public {
        MandateEvaluator implementation = new MandateEvaluator();
        _expectProxyInitializationRevert(
            address(implementation),
            abi.encodeCall(
                MandateEvaluator.initialize, (address(this), address(0), address(0), 0, address(0), address(this))
            )
        );
    }

    function test_escalationProxyInitializationRejectsZeroEvaluator() public {
        EscalationManager implementation = new EscalationManager();
        _expectProxyInitializationRevert(
            address(implementation),
            abi.encodeCall(EscalationManager.initialize, (address(this), address(0), address(this), address(this)))
        );
    }

    function test_executorProxyInitializationRejectsZeroEscalationManager() public {
        VaultExecutor implementation = new VaultExecutor();
        _expectProxyInitializationRevert(
            address(implementation),
            abi.encodeCall(
                VaultExecutor.initialize, (address(this), address(this), address(this), address(0), address(this))
            )
        );
    }

    function test_factoryProxyInitializationRejectsZeroExecutor() public {
        VaultFactory implementation = new VaultFactory();
        Vault vaultImplementation = new Vault();
        _expectProxyInitializationRevert(
            address(implementation),
            abi.encodeCall(
                VaultFactory.initialize,
                (address(this), address(vaultImplementation), 1, address(0), address(this), address(this))
            )
        );
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
        fixture.admin
            .configureModules(
                registry, evaluator, escalationManager, executor, vaultFactory, new ActionTypes.SwapAdapterConfig[](0)
            );
    }

    function test_adminRejectsInvalidAndDuplicateSwapAdapterInputs() public {
        (Grantline hub, GrantlineAdmin admin) = _unconfiguredHub();
        ActionTypes.SwapAdapterConfig[] memory adapters = new ActionTypes.SwapAdapterConfig[](1);
        adapters[0] = ActionTypes.SwapAdapterConfig({
            swapAdapterId: ActionTypes.SwapAdapterId.UNISWAP_V3, swapAdapter: address(0)
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                GrantlineAdmin.InvalidSwapAdapter.selector, ActionTypes.SwapAdapterId.UNISWAP_V3, address(0)
            )
        );
        admin.configureModules(address(1), address(2), address(3), address(4), address(5), adapters);
        assert(!hub.configured());

        GrantlineSwapConfigMock adapter = new GrantlineSwapConfigMock(address(hub));
        adapters = new ActionTypes.SwapAdapterConfig[](2);
        adapters[0] = ActionTypes.SwapAdapterConfig({
            swapAdapterId: ActionTypes.SwapAdapterId.UNISWAP_V3, swapAdapter: address(adapter)
        });
        adapters[1] = adapters[0];

        fixtureVm.expectRevert(
            abi.encodeWithSelector(GrantlineAdmin.DuplicateSwapAdapter.selector, ActionTypes.SwapAdapterId.UNISWAP_V3)
        );
        admin.configureModules(address(1), address(2), address(3), address(4), address(5), adapters);
        assert(!hub.configured());
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

        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.NotProtocolAdmin.selector, address(this)));
        fixture.admin.setVaultController(fixture.vault, address(0xBEEF));

        fixtureVm.prank(nextAdmin);
        fixture.admin.setVaultController(fixture.vault, address(0xBEEF));
        assert(fixture.hub.getVault(fixture.vault).controller == address(0xBEEF));
    }

    function test_facadeReadsAndAdminControllerValidation() public {
        Fixture memory fixture = _fixture();

        assert(fixture.hub.protocolAdmin() == address(this));
        assert(fixture.hub.version() == 1);
        assert(fixture.hub.moduleVersion(fixture.hub.REGISTRY_MODULE()) == 1);
        uint256[] memory lineage = fixture.hub.getLineage(fixture.mandateId);
        assert(lineage.length == 1);
        assert(lineage[0] == fixture.mandateId);

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.UnknownModule.selector, bytes32(uint256(1))));
        fixture.hub.moduleVersion(bytes32(uint256(1)));

        fixture.admin.validateWiring();

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidAdminController.selector));
        fixture.hub.setAdminController(address(0));

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidAdminController.selector));
        fixture.hub.setAdminController(address(fixture.hub));

        GrantlineAdmin wrongAdmin = new GrantlineAdmin(address(new Grantline()));
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidAdminController.selector));
        fixture.hub.setAdminController(address(wrongAdmin));
    }

    function test_adminControllerHandoverMigratesModulesAtomically() public {
        Fixture memory fixture = _fixture();
        GrantlineAdmin nextAdmin = new GrantlineAdmin(address(fixture.hub));
        address[] memory vaults = new address[](1);
        vaults[0] = fixture.vault;

        fixture.hub.setAdminController(address(nextAdmin));

        assert(fixture.hub.adminController() == address(nextAdmin));
        assert(MandateRegistry(fixture.hub.registry()).owner() == address(nextAdmin));
        assert(MandateEvaluator(fixture.hub.evaluator()).owner() == address(nextAdmin));
        assert(EscalationManager(fixture.hub.escalationManager()).owner() == address(nextAdmin));
        assert(VaultExecutor(fixture.hub.executor()).owner() == address(nextAdmin));
        assert(VaultFactory(fixture.hub.vaultFactory()).owner() == address(nextAdmin));
        assert(VaultFactory(fixture.hub.vaultFactory()).upgradeAuthority() == address(nextAdmin));
        assert(Vault(payable(fixture.vault)).upgradeAuthority() == address(fixture.admin));

        fixtureVm.expectRevert();
        fixture.admin.validateWiring();

        nextAdmin.validateWiring();
        GrantlineProtocolRegistryV2 registryImplementation = new GrantlineProtocolRegistryV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(registryImplementation), version: 1, data: ""
        });
        nextAdmin.upgradeModules(upgrades);
        assert(GrantlineProtocolRegistryV2(fixture.hub.registry()).marker() == 2);

        fixture.admin.migrateVaultUpgradeAuthorities(vaults, address(nextAdmin));
        assert(Vault(payable(fixture.vault)).upgradeAuthority() == address(nextAdmin));

        address futureVault = fixture.hub.createVault();
        assert(Vault(payable(futureVault)).upgradeAuthority() == address(nextAdmin));
    }

    function test_adminControllerHandoverRollsBackWhenNewAdminCannotAccept() public {
        Fixture memory fixture = _fixture();
        GrantlineNoopAdmin nextAdmin = new GrantlineNoopAdmin(address(fixture.hub));

        fixtureVm.expectRevert();
        fixture.hub.setAdminController(address(nextAdmin));

        assert(fixture.hub.adminController() == address(fixture.admin));
        assert(MandateRegistry(fixture.hub.registry()).owner() == address(fixture.admin));
        assert(MandateRegistry(fixture.hub.registry()).pendingOwner() == address(0));
        assert(VaultFactory(fixture.hub.vaultFactory()).owner() == address(fixture.admin));
        assert(VaultFactory(fixture.hub.vaultFactory()).upgradeAuthority() == address(fixture.admin));
    }

    function test_adminRejectsUnauthorizedUnknownAndUnregisteredOperations() public {
        Fixture memory fixture = _fixture();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] =
            GrantlineAdmin.ModuleUpgrade({key: bytes32(uint256(1)), implementation: address(0), version: 1, data: ""});

        fixtureVm.prank(address(0xCAFE));
        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.NotProtocolAdmin.selector, address(0xCAFE)));
        fixture.admin.validateWiring();

        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.UnknownModule.selector, bytes32(uint256(1))));
        fixture.admin.upgradeModules(upgrades);

        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.VaultNotRegistered.selector, address(0xCAFE)));
        fixture.admin.upgradeVault(address(0xCAFE), address(0), 1, "");
    }

    function test_adminRejectsInvalidHubAndPreConfigurationMutation() public {
        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.InvalidAddress.selector));
        new GrantlineAdmin(address(0));

        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.InvalidAddress.selector));
        new GrantlineAdmin(address(0xCAFE));

        Grantline implementation = new Grantline();
        Grantline hub = Grantline(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(Grantline.initialize, (address(this)))))
        );
        GrantlineAdmin admin = new GrantlineAdmin(address(hub));

        fixtureVm.expectRevert(abi.encodeWithSelector(GrantlineAdmin.InvalidModule.selector, bytes32(0), address(0)));
        admin.setVaultImplementation(address(0xBEEF), 1);
    }

    function test_vaultInitializationAndFactoryValidationRejectBadInputs() public {
        Fixture memory fixture = _fixture();
        Vault implementation = new Vault();
        address executor = fixture.hub.executor();

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        _deployVaultProxy(address(implementation), address(0), executor, address(fixture.admin));

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        _deployVaultProxy(address(implementation), address(fixture.hub), address(0), address(fixture.admin));

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        _deployVaultProxy(address(implementation), address(fixture.hub), executor, address(0xCAFE));

        VaultFactory factory = VaultFactory(fixture.hub.vaultFactory());
        fixtureVm.prank(address(0xCAFE));
        fixtureVm.expectRevert();
        factory.validateVaultImplementation(address(implementation), 1);

        GrantlineWrongUuidVaultImplementation wrongUuid = new GrantlineWrongUuidVaultImplementation();
        fixtureVm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(wrongUuid)));
        fixture.admin.setVaultImplementation(address(wrongUuid), 1);

        fixtureVm.prank(address(fixture.hub));
        fixtureVm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidAddress.selector));
        factory.createVault(address(0));
    }

    function test_factoryRejectsIncompleteOrPausedVaultInterfaces() public {
        Fixture memory fixture = _fixture();
        GrantlineMissingUnpauseVaultImplementation missingUnpause = new GrantlineMissingUnpauseVaultImplementation();
        GrantlinePausedVaultImplementation pausedImplementation = new GrantlinePausedVaultImplementation();

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(missingUnpause))
        );
        fixture.admin.setVaultImplementation(address(missingUnpause), 1);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(pausedImplementation))
        );
        fixture.admin.setVaultImplementation(address(pausedImplementation), 1);
    }

    function test_rejectsVaultImplementationsMissingSwapEntrypoints() public {
        Fixture memory fixture = _fixture();
        GrantlineMissingExecuteSwapVaultImplementation missingExecuteSwap =
            new GrantlineMissingExecuteSwapVaultImplementation();
        GrantlineMissingSwapNativeReceiverVaultImplementation missingNativeReceiver =
            new GrantlineMissingSwapNativeReceiverVaultImplementation();
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(missingExecuteSwap))
        );
        fixture.admin.setVaultImplementation(address(missingExecuteSwap), 1);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(missingNativeReceiver))
        );
        fixture.admin.upgradeVault(fixture.vault, address(missingNativeReceiver), 1, "");

        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);
    }

    function test_factoryModuleUpgradePreservesTemplateValidation() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultFactoryV2 implementation = new GrantlineProtocolVaultFactoryV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.VAULT_FACTORY_MODULE(), implementation: address(implementation), version: 1, data: ""
        });

        fixture.admin.upgradeModules(upgrades);
        assert(GrantlineProtocolVaultFactoryV2(fixture.hub.vaultFactory()).marker() == 2);
        assert(VaultFactory(fixture.hub.vaultFactory()).vaultImplementationVersion() == 1);
    }

    function _deployVaultProxy(address implementation, address grantline, address authority, address upgradeAuthority)
        private
        returns (address)
    {
        return address(
            new ERC1967Proxy(implementation, abi.encodeCall(Vault.initialize, (grantline, authority, upgradeAuthority)))
        );
    }

    function _expectProxyInitializationRevert(address implementation, bytes memory data) private {
        bool reverted;
        try new ERC1967Proxy(implementation, data) returns (ERC1967Proxy) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    function test_adminBoundaryKeepsUserFacadeAndVaultCustodySeparate() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();

        assert(MandateRegistry(fixture.hub.registry()).owner() == address(fixture.admin));
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).upgradeAuthority() == address(fixture.admin));

        fixtureVm.prank(address(fixture.admin));
        fixtureVm.expectRevert();
        Vault(payable(fixture.vault)).withdrawNative(payable(address(0xBEEF)), 1);

        fixtureVm.prank(address(fixture.hub));
        (bool hubUpgradeSuccess,) = address(fixture.vault)
            .call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(implementation), bytes("")));
        assert(!hubUpgradeSuccess);

        (bool legacyAdminSuccess,) = address(fixture.hub)
            .call(abi.encodeWithSignature("setVaultController(address,address)", fixture.vault, address(0xBEEF)));
        assert(!legacyAdminSuccess);
        (bool adminPauseSuccess,) =
            address(fixture.admin).call(abi.encodeWithSignature("pauseVault(address)", fixture.vault));
        assert(!adminPauseSuccess);
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
        fixture.admin.setVaultController(address(0xCAFE), address(0xBEEF));

        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.InvalidController.selector));
        fixture.admin.setVaultController(fixture.vault, address(0));

        fixtureVm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(0)));
        fixture.admin.setVaultImplementation(address(0), 1);
    }

    function test_rejectsWrongRoleModuleImplementation() public {
        Fixture memory fixture = _fixture();
        VaultExecutor implementation = new VaultExecutor();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(implementation), version: 1, data: ""
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                GrantlineAdmin.InvalidComponentType.selector,
                "module.implementation",
                ComponentTypes.REGISTRY,
                ComponentTypes.EXECUTOR
            )
        );
        fixture.admin.upgradeModules(upgrades);

        assert(MandateRegistry(fixture.hub.registry()).componentType() == ComponentTypes.REGISTRY);
    }

    function test_rejectsWrongRoleVaultImplementations() public {
        Fixture memory fixture = _fixture();
        VaultExecutor implementation = new VaultExecutor();

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.admin.setVaultImplementation(address(implementation), 1);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.admin.upgradeVault(fixture.vault, address(implementation), 1, "");

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
        fixture.admin.setVaultImplementation(address(implementation), 1);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.admin.upgradeVault(fixture.vault, address(implementation), 1, "");

        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).authority() == fixture.hub.executor());
    }

    function test_moduleUpgradeRejectsExternalModuleOwner() public {
        Fixture memory fixture = _fixture();
        GrantlineRegistryOwnershipV2 implementation = new GrantlineRegistryOwnershipV2();
        address externalOwner = address(0xBEEF);
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineRegistryOwnershipV2.setOwnerForTest, (externalOwner))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                GrantlineAdmin.InvalidModuleOwner.selector,
                ComponentTypes.REGISTRY,
                address(fixture.admin),
                externalOwner
            )
        );
        fixture.admin.upgradeModules(upgrades);

        assert(MandateRegistry(fixture.hub.registry()).owner() == address(fixture.admin));
        assert(MandateRegistry(fixture.hub.registry()).mandateCount() == 1);
        (bool markerPresent,) = fixture.hub.registry().call(abi.encodeCall(GrantlineRegistryOwnershipV2.marker, ()));
        assert(!markerPresent);
    }

    function test_moduleUpgradeRejectsPendingModuleOwner() public {
        Fixture memory fixture = _fixture();
        GrantlineRegistryOwnershipV2 implementation = new GrantlineRegistryOwnershipV2();
        address pendingOwner = address(0xCAFE);
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineRegistryOwnershipV2.setPendingOwnerForTest, (pendingOwner))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(
                GrantlineAdmin.InvalidModulePendingOwner.selector, ComponentTypes.REGISTRY, pendingOwner
            )
        );
        fixture.admin.upgradeModules(upgrades);

        assert(MandateRegistry(fixture.hub.registry()).owner() == address(fixture.admin));
        assert(MandateRegistry(fixture.hub.registry()).pendingOwner() == address(0));
    }

    function test_moduleUpgradeRejectsManagerRegistryMismatch() public {
        Fixture memory fixture = _fixture();
        GrantlineEscalationRegistryV2 implementation = new GrantlineEscalationRegistryV2();
        address alternateRegistry = address(new MandateRegistry());
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.ESCALATION_MANAGER_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineEscalationRegistryV2.setRegistryForTest, (alternateRegistry))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(GrantlineAdmin.InvalidModuleRelationship.selector, "manager.registry")
        );
        fixture.admin.upgradeModules(upgrades);

        assert(EscalationManager(fixture.hub.escalationManager()).registry() == fixture.hub.registry());
    }

    function test_moduleUpgradeRejectsExecutorRegistryMismatch() public {
        Fixture memory fixture = _fixture();
        GrantlineExecutorRegistryV2 implementation = new GrantlineExecutorRegistryV2();
        address alternateRegistry = address(new MandateRegistry());
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.EXECUTOR_MODULE(),
            implementation: address(implementation),
            version: 1,
            data: abi.encodeCall(GrantlineExecutorRegistryV2.setRegistryForTest, (alternateRegistry))
        });

        fixtureVm.expectRevert(
            abi.encodeWithSelector(GrantlineAdmin.InvalidModuleRelationship.selector, "executor.registry")
        );
        fixture.admin.upgradeModules(upgrades);

        assert(VaultExecutor(fixture.hub.executor()).registry() == fixture.hub.registry());
    }

    function test_factoryTemplateOnlyAffectsFutureVaults() public {
        Fixture memory fixture = _fixture();
        address existingVault = fixture.vault;
        address secondVault = fixture.hub.createVault();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();

        fixture.admin.setVaultImplementation(address(implementation), 1);
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

        fixtureVm.expectRevert();
        fixture.admin.setVaultImplementation(address(implementation), 1);

        assert(fixture.hub.vaultCount() == previousHubVaultCount);
        assert(VaultFactory(fixture.hub.vaultFactory()).vaultCount() == previousFactoryVaultCount);
        assert(fixture.hub.vaultAt(0) == fixture.vault);
    }

    function test_rejectsVaultTemplateWithWrongUpgradeAuthority() public {
        Fixture memory fixture = _fixture();
        GrantlineWrongUpgradeAuthorityVaultImplementation implementation =
            new GrantlineWrongUpgradeAuthorityVaultImplementation();
        address previousImplementation = VaultFactory(fixture.hub.vaultFactory()).vaultImplementation();

        fixtureVm.expectRevert(
            abi.encodeWithSelector(VaultFactory.InvalidImplementation.selector, address(implementation))
        );
        fixture.admin.setVaultImplementation(address(implementation), 1);

        assert(VaultFactory(fixture.hub.vaultFactory()).vaultImplementation() == previousImplementation);
        assert(fixture.hub.createVault() != address(0));
    }

    function test_existingVaultUpgradePreservesStateAndChecksVersion() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;

        fixtureVm.expectRevert();
        fixture.admin.upgradeVault(fixture.vault, address(implementation), 2, "");
        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);

        fixture.admin.upgradeVault(fixture.vault, address(implementation), 1, "");
        assert(GrantlineProtocolVaultV2(payable(fixture.vault)).marker() == 2);
        assert(fixture.hub.getVault(fixture.vault).implementation == address(implementation));
    }

    function test_existingVaultUpgradeRejectsPendingOwner() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolVaultV2 implementation = new GrantlineProtocolVaultV2();
        address pendingOwner = address(0xCAFE);
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;

        fixtureVm.expectRevert();
        fixture.admin
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
        fixtureVm.expectRevert();
        fixture.admin
            .upgradeVault(
                fixture.vault, address(implementation), 1, abi.encodeCall(GrantlineProtocolOwnership.unpause, ())
            );

        assert(Vault(payable(fixture.vault)).paused());
        assert(fixture.hub.getVault(fixture.vault).implementation != address(implementation));
    }

    function test_moduleUpgradeIsAtomicAndPreservesRegistryStorage() public {
        Fixture memory fixture = _fixture();
        GrantlineProtocolRegistryV2 implementation = new GrantlineProtocolRegistryV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(implementation), version: 2, data: ""
        });

        fixtureVm.expectRevert();
        fixture.admin.upgradeModules(upgrades);
        (bool markerPresent,) = fixture.hub.registry().call(abi.encodeCall(GrantlineProtocolRegistryV2.marker, ()));
        assert(!markerPresent);

        upgrades[0].version = 1;
        fixture.admin.upgradeModules(upgrades);
        assert(GrantlineProtocolRegistryV2(fixture.hub.registry()).marker() == 2);
        assert(MandateRegistry(fixture.hub.registry()).mandateCount() == 1);
        assert(MandateRegistry(fixture.hub.registry()).isRegisteredVault(fixture.vault));
    }

    function test_controllerReassignmentChangesOnlyControllerAuthority() public {
        Fixture memory fixture = _fixture();
        address nextController = address(0xCAFE);
        fixture.admin.setVaultController(fixture.vault, nextController);
        assert(fixture.hub.controllerOf(fixture.vault) == nextController);
        assert(Vault(payable(fixture.vault)).owner() == address(fixture.hub));
        assert(Vault(payable(fixture.vault)).authority() == fixture.hub.executor());

        fixtureVm.expectRevert();
        fixture.hub.depositNative{value: 0}(fixture.vault);
    }

    function _unconfiguredHub() private returns (Grantline hub, GrantlineAdmin admin) {
        Grantline implementation = new Grantline();
        hub = Grantline(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(Grantline.initialize, (address(this)))))
        );
        admin = new GrantlineAdmin(address(hub));
        hub.setAdminController(address(admin));
    }
}
