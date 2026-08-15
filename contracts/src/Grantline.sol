// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ActionSignature} from "./ActionSignature.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";
import {
    IComponent,
    IGrantlineContext,
    IEscalationManager,
    IEvaluator,
    IExecutor,
    IModule,
    IOwnable2Step,
    IRegistry,
    IUUPS,
    IVault,
    IVaultFactory
} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

contract Grantline is
    Initializable,
    GrantlineOwnable2StepUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    EIP712Upgradeable,
    IGrantlineContext
{
    bytes32 public constant REGISTRY_MODULE = ComponentTypes.REGISTRY;
    bytes32 public constant EVALUATOR_MODULE = ComponentTypes.EVALUATOR;
    bytes32 public constant ESCALATION_MANAGER_MODULE = ComponentTypes.ESCALATION_MANAGER;
    bytes32 public constant EXECUTOR_MODULE = ComponentTypes.EXECUTOR;
    bytes32 public constant VAULT_FACTORY_MODULE = ComponentTypes.VAULT_FACTORY;

    error InvalidAddress();
    error InvalidModule(bytes32 key, address module);
    error InvalidComponentType(string component, bytes32 expected, bytes32 actual);
    error InvalidModuleOwner(bytes32 key, address expected, address actual);
    error InvalidModulePendingOwner(bytes32 key, address pendingOwner);
    error InvalidModuleRelationship(string relationship);
    error AlreadyConfigured();
    error NotConfigured();
    error UnknownModule(bytes32 key);
    error VaultNotRegistered(address vault);
    error NotController(address vault, address caller);
    error NotParentAgent(uint256 mandateId, address caller);
    error NotMandateAdministrator(uint256 mandateId, address caller);
    error InvalidController();

    event ModulesConfigured(
        address indexed registry,
        address indexed evaluator,
        address escalationManager,
        address executor,
        address vaultFactory
    );
    event VaultCreated(
        address indexed vault,
        address indexed controller,
        address indexed owner,
        address authority,
        address implementation,
        uint64 version
    );
    event VaultControllerUpdated(
        address indexed vault, address indexed previousController, address indexed newController
    );
    event ActionPlanSubmitted(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed agent, address submittedBy
    );
    event ActionPlanExecuted(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed agent, address vault, uint256 nonce
    );

    struct ModuleUpgrade {
        bytes32 key;
        address implementation;
        uint64 version;
        bytes data;
    }

    struct VaultRecord {
        address controller;
        address implementation;
        uint64 version;
    }

    struct VaultView {
        address vault;
        address controller;
        address owner;
        address authority;
        address implementation;
        uint64 version;
        uint256 nativeBalance;
    }

    mapping(bytes32 => address) private _modules;
    mapping(address => VaultRecord) private _vaultRecords;
    address[] private _vaults;
    bool public configured;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialProtocolAdmin) external initializer {
        if (initialProtocolAdmin == address(0)) revert InvalidAddress();
        __Ownable_init(initialProtocolAdmin);
        __Ownable2Step_init();
        __EIP712_init("Grantline", "1");
    }

    function protocolAdmin() external view returns (address) {
        return owner();
    }

    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.GRANTLINE;
    }

    function configureModules(
        address registryAddress,
        address evaluatorAddress,
        address escalationManagerAddress,
        address executorAddress,
        address vaultFactoryAddress
    ) external onlyOwner {
        if (configured) revert AlreadyConfigured();
        _modules[REGISTRY_MODULE] = registryAddress;
        _modules[EVALUATOR_MODULE] = evaluatorAddress;
        _modules[ESCALATION_MANAGER_MODULE] = escalationManagerAddress;
        _modules[EXECUTOR_MODULE] = executorAddress;
        _modules[VAULT_FACTORY_MODULE] = vaultFactoryAddress;
        _validateWiring();
        configured = true;
        emit ModulesConfigured(
            registryAddress, evaluatorAddress, escalationManagerAddress, executorAddress, vaultFactoryAddress
        );
    }

    function moduleAddress(bytes32 key) public view override returns (address) {
        return _modules[key];
    }

    function registry() public view returns (address) {
        return _modules[REGISTRY_MODULE];
    }

    function evaluator() public view returns (address) {
        return _modules[EVALUATOR_MODULE];
    }

    function escalationManager() public view returns (address) {
        return _modules[ESCALATION_MANAGER_MODULE];
    }

    function executor() public view returns (address) {
        return _modules[EXECUTOR_MODULE];
    }

    function vaultFactory() public view returns (address) {
        return _modules[VAULT_FACTORY_MODULE];
    }

    function createVault() external nonReentrant returns (address vault) {
        _onlyConfigured();
        address controller = msg.sender;
        vault = IVaultFactory(vaultFactory()).createVault(controller);
        IRegistry(registry()).registerVault(vault);
        address implementation = IVaultFactory(vaultFactory()).vaultImplementation();
        uint64 vaultVersion = IVaultFactory(vaultFactory()).vaultImplementationVersion();
        _vaultRecords[vault] =
            VaultRecord({controller: controller, implementation: implementation, version: vaultVersion});
        _vaults.push(vault);
        emit VaultCreated(
            vault, controller, IVault(vault).owner(), IVault(vault).authority(), implementation, vaultVersion
        );
    }

    function depositNative(address vault) external payable nonReentrant {
        _onlyController(vault, msg.sender);
        IVault(vault).depositNative{value: msg.value}(msg.sender);
    }

    function depositToken(address vault, address token, uint256 amount) external nonReentrant {
        _onlyController(vault, msg.sender);
        IVault(vault).depositTokenFrom(msg.sender, token, amount);
    }

    function withdrawNative(address vault, address payable recipient, uint256 amount) external nonReentrant {
        _onlyController(vault, msg.sender);
        IVault(vault).withdrawNative(recipient, amount);
    }

    function withdrawToken(address vault, address token, address recipient, uint256 amount) external nonReentrant {
        _onlyController(vault, msg.sender);
        IVault(vault).withdrawToken(token, recipient, amount);
    }

    function createMandate(
        address vault,
        address agent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules
    ) external nonReentrant returns (uint256 mandateId) {
        _onlyController(vault, msg.sender);
        mandateId = IRegistry(registry()).createMandate(vault, msg.sender, agent, rules, preflightRules);
    }

    function createChildMandate(
        uint256 parentMandateId,
        address childAgent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules
    ) external nonReentrant returns (uint256 mandateId) {
        GrantlineTypes.Mandate memory parent = IRegistry(registry()).getMandate(parentMandateId);
        if (parent.agent != msg.sender) {
            revert NotParentAgent(parentMandateId, msg.sender);
        }
        if (!IRegistry(registry()).isLineageActive(parentMandateId)) {
            revert NotParentAgent(parentMandateId, msg.sender);
        }
        mandateId =
            IRegistry(registry()).createChildMandate(parentMandateId, msg.sender, childAgent, rules, preflightRules);
    }

    function updateMandate(
        uint256 mandateId,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules
    ) external nonReentrant {
        _requireMandateAdministrator(mandateId, msg.sender);
        IRegistry(registry()).updateMandate(mandateId, msg.sender, rules, preflightRules);
    }

    function revokeMandate(uint256 mandateId) external nonReentrant {
        _requireMandateAdministrator(mandateId, msg.sender);
        IRegistry(registry()).revokeMandate(mandateId, msg.sender);
    }

    function submitEscalation(ActionTypes.ActionPlan calldata plan, bytes calldata signature)
        external
        nonReentrant
        returns (bytes32 digest)
    {
        _onlyConfigured();
        digest = actionDigest(plan);
        IEscalationManager(escalationManager()).submit(plan, signature, digest, msg.sender);
        emit ActionPlanSubmitted(digest, plan.mandateId, plan.agent, msg.sender);
    }

    function approveEscalation(bytes32 digest) external nonReentrant {
        _onlyConfigured();
        GrantlineTypes.Escalation memory escalation = IEscalationManager(escalationManager()).getEscalation(digest);
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(escalation.plan.mandateId);
        _onlyController(mandate.vault, msg.sender);
        IEscalationManager(escalationManager()).approve(digest, msg.sender);
    }

    function denyEscalation(bytes32 digest) external nonReentrant {
        _onlyConfigured();
        GrantlineTypes.Escalation memory escalation = IEscalationManager(escalationManager()).getEscalation(digest);
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(escalation.plan.mandateId);
        _onlyController(mandate.vault, msg.sender);
        IEscalationManager(escalationManager()).deny(digest, msg.sender);
    }

    function execute(ActionTypes.ActionPlan calldata plan, bytes calldata signature)
        external
        nonReentrant
        returns (bytes32 digest)
    {
        _onlyConfigured();
        digest = actionDigest(plan);
        IExecutor(executor()).execute(plan, signature, digest);
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(plan.mandateId);
        emit ActionPlanExecuted(digest, plan.mandateId, plan.agent, mandate.vault, plan.nonce);
    }

    function executeEscalated(bytes32 digest) external nonReentrant returns (bytes32 executedDigest) {
        _onlyConfigured();
        IExecutor(executor()).executeEscalated(digest);
        executedDigest = digest;
        GrantlineTypes.Escalation memory escalation = IEscalationManager(escalationManager()).getEscalation(digest);
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(escalation.plan.mandateId);
        emit ActionPlanExecuted(
            digest, escalation.plan.mandateId, escalation.plan.agent, mandate.vault, escalation.plan.nonce
        );
    }

    function actionDigest(ActionTypes.ActionPlan calldata plan) public view override returns (bytes32) {
        return _hashTypedDataV4(ActionSignature.hashActionPlan(plan));
    }

    function evaluate(ActionTypes.ActionPlan calldata plan, bytes calldata signature)
        external
        view
        returns (GrantlineTypes.EvaluationResult memory)
    {
        _onlyConfigured();
        return IEvaluator(evaluator()).evaluate(plan, signature, actionDigest(plan));
    }

    function getMandate(uint256 mandateId) external view returns (GrantlineTypes.MandateView memory viewData) {
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(mandateId);
        viewData = GrantlineTypes.MandateView({
            id: mandate.id,
            controller: controllerOf(mandate.vault),
            vault: mandate.vault,
            agent: mandate.agent,
            parentMandateId: mandate.parentMandateId,
            delegationDepth: mandate.delegationDepth,
            status: mandate.status,
            rules: mandate.rules,
            preflightRules: mandate.preflightRules,
            createdAt: mandate.createdAt,
            revokedAt: mandate.revokedAt
        });
    }

    function getLineage(uint256 mandateId) external view returns (uint256[] memory) {
        return IRegistry(registry()).getLineage(mandateId);
    }

    function getEffectiveRules(uint256 mandateId) external view returns (GrantlineTypes.MandateRules memory) {
        return IRegistry(registry()).getEffectiveRules(mandateId);
    }

    function getEffectivePreflightRules(uint256 mandateId)
        external
        view
        returns (GrantlineTypes.PreflightRules memory)
    {
        return IRegistry(registry()).getEffectivePreflightRules(mandateId);
    }

    function getEscalation(bytes32 digest) external view returns (GrantlineTypes.Escalation memory) {
        return IEscalationManager(escalationManager()).getEscalation(digest);
    }

    function escalationStatus(bytes32 digest) external view returns (uint8) {
        return IEscalationManager(escalationManager()).getEscalation(digest).status;
    }

    function vaultCount() external view returns (uint256) {
        return _vaults.length;
    }

    function vaultAt(uint256 index) external view returns (address) {
        return _vaults[index];
    }

    function isRegisteredVault(address vault) external view returns (bool) {
        return _vaultRecords[vault].controller != address(0);
    }

    function controllerOf(address vault) public view override returns (address) {
        return _vaultRecords[vault].controller;
    }

    function isController(address vault, address account) public view override returns (bool) {
        return controllerOf(vault) == account && account != address(0);
    }

    function getVault(address vault) external view returns (VaultView memory viewData) {
        VaultRecord memory record = _vaultRecords[vault];
        if (record.controller == address(0)) revert VaultNotRegistered(vault);
        viewData = VaultView({
            vault: vault,
            controller: record.controller,
            owner: IVault(vault).owner(),
            authority: IVault(vault).authority(),
            implementation: record.implementation,
            version: record.version,
            nativeBalance: vault.balance
        });
    }

    function moduleVersion(bytes32 key) external view returns (uint64) {
        address module = _modules[key];
        if (module == address(0)) revert UnknownModule(key);
        return IModule(module).version();
    }

    function upgradeModules(ModuleUpgrade[] calldata upgrades) external onlyOwner {
        _onlyConfigured();
        for (uint256 index; index < upgrades.length; index++) {
            if (!_isKnownModule(upgrades[index].key)) {
                revert UnknownModule(upgrades[index].key);
            }
            address module = _modules[upgrades[index].key];
            IUUPS(module).upgradeToAndCall(upgrades[index].implementation, upgrades[index].data);
            if (IModule(module).version() != upgrades[index].version) {
                revert InvalidModuleRelationship("module.version");
            }
        }
        _validateWiring();
    }

    /// @dev Changes the implementation used for future Vault proxies only.
    function setVaultImplementation(address implementation, uint64 implementationVersion) external onlyOwner {
        _onlyConfigured();
        IVaultFactory(vaultFactory()).setVaultImplementation(implementation, implementationVersion);
    }

    /// @dev Upgrades one existing Vault proxy and preserves its recorded identity.
    function upgradeVault(address vault, address implementation, uint64 implementationVersion, bytes calldata data)
        external
        onlyOwner
        nonReentrant
    {
        _onlyConfigured();
        if (_vaultRecords[vault].controller == address(0)) {
            revert VaultNotRegistered(vault);
        }
        _requireComponentType(implementation, ComponentTypes.VAULT, "vault.implementation");
        _requireImplementationVersion(implementation, implementationVersion);

        // The record is updated before the external upgrade call. If the UUPS upgrade or
        // its optional initializer reverts, transaction atomicity restores the old record.
        _vaultRecords[vault].implementation = implementation;
        _vaultRecords[vault].version = implementationVersion;
        IUUPS(vault).upgradeToAndCall(implementation, data);
        _requireComponentType(vault, ComponentTypes.VAULT, "vault");
        if (IVault(vault).version() != implementationVersion) {
            revert InvalidModuleRelationship("vault.version");
        }
        if (IVault(vault).owner() != address(this)) {
            revert InvalidModuleRelationship("vault.owner");
        }
        if (IOwnable2Step(vault).pendingOwner() != address(0)) {
            revert InvalidModuleRelationship("vault.pendingOwner");
        }
        if (IVault(vault).authority() != executor()) {
            revert InvalidModuleRelationship("vault.authority");
        }
    }

    /// @dev Changes only the controller authorised for one existing Vault.
    function setVaultController(address vault, address newController) external onlyOwner {
        _onlyConfigured();
        if (_vaultRecords[vault].controller == address(0)) {
            revert VaultNotRegistered(vault);
        }
        if (newController == address(0)) revert InvalidController();
        address previousController = _vaultRecords[vault].controller;
        _vaultRecords[vault].controller = newController;
        emit VaultControllerUpdated(vault, previousController, newController);
    }

    function _onlyController(address vault, address caller) private view {
        if (!_isRegistered(vault)) revert VaultNotRegistered(vault);
        if (!isController(vault, caller)) revert NotController(vault, caller);
    }

    function _requireMandateAdministrator(uint256 mandateId, address caller) private view {
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(mandateId);
        if (isController(mandate.vault, caller)) return;
        if (mandate.parentMandateId != 0) {
            GrantlineTypes.Mandate memory parent = IRegistry(registry()).getMandate(mandate.parentMandateId);
            if (parent.agent == caller && IRegistry(registry()).isLineageActive(mandate.parentMandateId)) {
                return;
            }
        }
        revert NotMandateAdministrator(mandateId, caller);
    }

    function _isRegistered(address vault) private view returns (bool) {
        return _vaultRecords[vault].controller != address(0);
    }

    function _isKnownModule(bytes32 key) private pure returns (bool) {
        return key == REGISTRY_MODULE || key == EVALUATOR_MODULE || key == ESCALATION_MANAGER_MODULE
            || key == EXECUTOR_MODULE || key == VAULT_FACTORY_MODULE;
    }

    function _onlyConfigured() private view {
        if (!configured) revert NotConfigured();
    }

    function _validateWiring() private view {
        address registryAddress = _modules[REGISTRY_MODULE];
        address evaluatorAddress = _modules[EVALUATOR_MODULE];
        address managerAddress = _modules[ESCALATION_MANAGER_MODULE];
        address executorAddress = _modules[EXECUTOR_MODULE];
        address factoryAddress = _modules[VAULT_FACTORY_MODULE];
        if (
            registryAddress == address(0) || evaluatorAddress == address(0) || managerAddress == address(0)
                || executorAddress == address(0) || factoryAddress == address(0)
        ) revert InvalidModule(bytes32(0), address(0));

        _requireModuleGrantline(registryAddress, REGISTRY_MODULE);
        _requireModuleGrantline(evaluatorAddress, EVALUATOR_MODULE);
        _requireModuleGrantline(managerAddress, ESCALATION_MANAGER_MODULE);
        _requireModuleGrantline(executorAddress, EXECUTOR_MODULE);
        _requireModuleGrantline(factoryAddress, VAULT_FACTORY_MODULE);

        _requireModuleOwnership(registryAddress, REGISTRY_MODULE);
        _requireModuleOwnership(evaluatorAddress, EVALUATOR_MODULE);
        _requireModuleOwnership(managerAddress, ESCALATION_MANAGER_MODULE);
        _requireModuleOwnership(executorAddress, EXECUTOR_MODULE);
        _requireModuleOwnership(factoryAddress, VAULT_FACTORY_MODULE);

        if (IEvaluator(evaluatorAddress).registry() != registryAddress) {
            revert InvalidModuleRelationship("evaluator.registry");
        }
        if (IEscalationManager(managerAddress).evaluator() != evaluatorAddress) {
            revert InvalidModuleRelationship("manager.evaluator");
        }
        if (IEscalationManager(managerAddress).registry() != registryAddress) {
            revert InvalidModuleRelationship("manager.registry");
        }
        if (IExecutor(executorAddress).evaluator() != evaluatorAddress) {
            revert InvalidModuleRelationship("executor.evaluator");
        }
        if (IExecutor(executorAddress).escalationManager() != managerAddress) {
            revert InvalidModuleRelationship("executor.manager");
        }
        if (IExecutor(executorAddress).registry() != registryAddress) {
            revert InvalidModuleRelationship("executor.registry");
        }
        if (IVaultFactory(factoryAddress).executor() != executorAddress) {
            revert InvalidModuleRelationship("factory.executor");
        }
    }

    function _requireModuleGrantline(address module, bytes32 key) private view {
        if (module.code.length == 0 || IModule(module).grantline() != address(this)) {
            revert InvalidModule(key, module);
        }
        _requireComponentType(module, key, "module");
    }

    function _requireModuleOwnership(address module, bytes32 key) private view {
        address moduleOwner = address(0);
        try IOwnable2Step(module).owner() returns (address actualOwner) {
            moduleOwner = actualOwner;
        } catch {
            revert InvalidModuleOwner(key, address(this), address(0));
        }
        if (moduleOwner != address(this)) {
            revert InvalidModuleOwner(key, address(this), moduleOwner);
        }

        address pendingOwner = address(0);
        try IOwnable2Step(module).pendingOwner() returns (address actualPendingOwner) {
            pendingOwner = actualPendingOwner;
        } catch {
            revert InvalidModulePendingOwner(key, address(0));
        }
        if (pendingOwner != address(0)) {
            revert InvalidModulePendingOwner(key, pendingOwner);
        }
    }

    function _requireComponentType(address target, bytes32 expected, string memory component) private view {
        bytes32 actual = bytes32(0);
        try IComponent(target).componentType() returns (bytes32 actualType) {
            actual = actualType;
        } catch {
            revert InvalidComponentType(component, expected, bytes32(0));
        }
        if (actual != expected) {
            revert InvalidComponentType(component, expected, actual);
        }
    }

    function _requireImplementationVersion(address implementation, uint64 expectedVersion) private pure {
        try IModule(implementation).version() returns (uint64 actualVersion) {
            if (actualVersion != expectedVersion) {
                revert InvalidModuleRelationship("implementation.version");
            }
        } catch {
            revert InvalidModuleRelationship("implementation.version");
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        _requireComponentType(newImplementation, ComponentTypes.GRANTLINE, "grantline.implementation");
    }
}
