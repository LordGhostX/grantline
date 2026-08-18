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
    IGrantlineAdmin,
    IGrantlineContext,
    IEscalationManager,
    IEvaluator,
    IExecutor,
    IModule,
    IRegistry,
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
    error InvalidComponentType(bytes32 component, bytes32 expected, bytes32 actual);
    error AlreadyConfigured();
    error NotConfigured();
    error UnknownModule(bytes32 key);
    error VaultNotRegistered(address vault);
    error NotController(address vault, address caller);
    error InvalidController();
    error VaultIsPaused(address vault);
    error InvalidAdminController();
    error NotAdminController(address caller);

    event ModulesConfigured(
        address indexed registry,
        address indexed evaluator,
        address escalationManager,
        address executor,
        address vaultFactory,
        uint256 swapAdapterCount
    );
    event AdminControllerUpdated(address indexed previousController, address indexed newController);
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
    event VaultPaused(address indexed vault, address indexed pausedBy);
    event VaultUnpaused(address indexed vault, address indexed unpausedBy);
    event MandatePaused(uint256 indexed mandateId, address indexed pausedBy);
    event MandateUnpaused(uint256 indexed mandateId, address indexed unpausedBy);
    event NonceCancelled(
        uint256 indexed mandateId, address indexed agent, uint256 indexed nonce, address cancelledBy, uint64 cancelledAt
    );
    event ActionPlanSubmitted(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed agent, address submittedBy
    );
    event ActionPlanExecuted(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed agent, address vault, uint256 nonce
    );

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
        bool paused;
    }

    mapping(bytes32 => address) private _modules;
    mapping(ActionTypes.SwapAdapterId => address) private _swapAdapters;
    mapping(address => VaultRecord) private _vaultRecords;
    address[] private _vaults;
    bool public configured;
    address public override adminController;

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

    function setAdminController(address newController) external onlyOwner {
        if (newController == address(0) || newController.code.length == 0) revert InvalidAdminController();
        try IGrantlineAdmin(newController).grantline() returns (address controllerGrantline) {
            if (controllerGrantline != address(this)) revert InvalidAdminController();
        } catch {
            revert InvalidAdminController();
        }
        address previousController = adminController;
        adminController = newController;
        emit AdminControllerUpdated(previousController, newController);
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
        address vaultFactoryAddress,
        ActionTypes.SwapAdapterConfig[] calldata swapAdapters
    ) external {
        _onlyAdminController();
        if (configured) revert AlreadyConfigured();
        if (
            registryAddress == address(0) || evaluatorAddress == address(0) || escalationManagerAddress == address(0)
                || executorAddress == address(0) || vaultFactoryAddress == address(0)
        ) revert InvalidAddress();
        _modules[REGISTRY_MODULE] = registryAddress;
        _modules[EVALUATOR_MODULE] = evaluatorAddress;
        _modules[ESCALATION_MANAGER_MODULE] = escalationManagerAddress;
        _modules[EXECUTOR_MODULE] = executorAddress;
        _modules[VAULT_FACTORY_MODULE] = vaultFactoryAddress;
        for (uint256 index; index < swapAdapters.length; index++) {
            ActionTypes.SwapAdapterConfig calldata config = swapAdapters[index];
            _swapAdapters[config.swapAdapterId] = config.swapAdapter;
        }
        configured = true;
        emit ModulesConfigured(
            registryAddress,
            evaluatorAddress,
            escalationManagerAddress,
            executorAddress,
            vaultFactoryAddress,
            swapAdapters.length
        );
    }

    function moduleAddress(bytes32 key) public view override returns (address) {
        return _modules[key];
    }

    function swapAdapterFor(ActionTypes.SwapAdapterId swapAdapterId) public view override returns (address) {
        return _swapAdapters[swapAdapterId];
    }

    function registry() public view returns (address) {
        return _modules[REGISTRY_MODULE];
    }

    function evaluator() public view returns (address) {
        return _modules[EVALUATOR_MODULE];
    }

    function getNativeUsdValuation()
        external
        view
        returns (bool enabled, address chainlinkFeed, uint8 feedDecimals, address wrappedNativeAddress)
    {
        IEvaluator evaluatorContract = IEvaluator(evaluator());
        enabled = evaluatorContract.nativeUsdValuationEnabled();
        chainlinkFeed = evaluatorContract.chainlinkNativeUsdFeed();
        feedDecimals = evaluatorContract.chainlinkNativeUsdFeedDecimals();
        wrappedNativeAddress = evaluatorContract.wrappedNative();
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

    function pauseVault(address vault) external nonReentrant {
        _onlyController(vault, msg.sender);
        IVault(vault).pause();
        emit VaultPaused(vault, msg.sender);
    }

    function unpauseVault(address vault) external nonReentrant {
        _onlyController(vault, msg.sender);
        IVault(vault).unpause();
        emit VaultUnpaused(vault, msg.sender);
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
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external nonReentrant returns (uint256 mandateId) {
        _onlyController(vault, msg.sender);
        _requireVaultNotPaused(vault);
        mandateId = IRegistry(registry())
            .createMandate(vault, msg.sender, agent, rules, preflightRules, validAfter, validUntil);
    }

    function createChildMandate(
        uint256 parentMandateId,
        address childAgent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external nonReentrant returns (uint256 mandateId) {
        GrantlineTypes.Mandate memory parent = IRegistry(registry()).getMandate(parentMandateId);
        _requireVaultNotPaused(parent.vault);
        mandateId = IRegistry(registry())
            .createChildMandate(parentMandateId, msg.sender, childAgent, rules, preflightRules, validAfter, validUntil);
    }

    function updateMandate(
        uint256 mandateId,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external nonReentrant {
        IRegistry(registry()).updateMandate(mandateId, msg.sender, rules, preflightRules, validAfter, validUntil);
    }

    function revokeMandate(uint256 mandateId) external nonReentrant {
        IRegistry(registry()).revokeMandate(mandateId, msg.sender);
    }

    function pauseMandate(uint256 mandateId) external nonReentrant {
        IRegistry(registry()).pauseMandate(mandateId, msg.sender);
        emit MandatePaused(mandateId, msg.sender);
    }

    function unpauseMandate(uint256 mandateId) external nonReentrant {
        IRegistry(registry()).unpauseMandate(mandateId, msg.sender);
        emit MandateUnpaused(mandateId, msg.sender);
    }

    function cancelNonce(uint256 mandateId, uint256 nonce) external nonReentrant {
        _onlyConfigured();
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(mandateId);
        IRegistry(registry()).cancelNonce(mandateId, msg.sender, nonce);
        emit NonceCancelled(mandateId, mandate.agent, nonce, msg.sender, uint64(block.timestamp));
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
        return IEvaluator(evaluator()).evaluate(plan, signature, actionDigest(plan), false);
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
            validAfter: mandate.validAfter,
            validUntil: mandate.validUntil,
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

    function getEffectiveValidityWindow(uint256 mandateId)
        external
        view
        returns (uint64 validAfter, uint64 validUntil)
    {
        return IRegistry(registry()).getEffectiveValidityWindow(mandateId);
    }

    function getNonceState(uint256 mandateId, uint256 nonce) external view returns (bool used, bytes32 reservation) {
        GrantlineTypes.Mandate memory mandate = IRegistry(registry()).getMandate(mandateId);
        IRegistry registryContract = IRegistry(registry());
        used = registryContract.nonceUsed(mandateId, mandate.agent, nonce);
        reservation = registryContract.reservedDigest(mandateId, mandate.agent, nonce);
    }

    function isLineageActive(uint256 mandateId) external view returns (bool) {
        return IRegistry(registry()).isLineageActive(mandateId);
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
            nativeBalance: vault.balance,
            paused: IVault(vault).paused()
        });
    }

    function moduleVersion(bytes32 key) external view returns (uint64) {
        address module = _modules[key];
        if (module == address(0)) revert UnknownModule(key);
        return IModule(module).version();
    }

    function adminSetVaultController(address vault, address newController) external {
        _onlyAdminController();
        _onlyConfigured();
        if (_vaultRecords[vault].controller == address(0)) revert VaultNotRegistered(vault);
        if (newController == address(0)) revert InvalidController();
        address previousController = _vaultRecords[vault].controller;
        _vaultRecords[vault].controller = newController;
        emit VaultControllerUpdated(vault, previousController, newController);
    }

    function adminRecordVaultUpgrade(address vault, address implementation, uint64 implementationVersion) external {
        _onlyAdminController();
        _onlyConfigured();
        if (_vaultRecords[vault].controller == address(0)) {
            revert VaultNotRegistered(vault);
        }
        _vaultRecords[vault].implementation = implementation;
        _vaultRecords[vault].version = implementationVersion;
    }

    function _onlyController(address vault, address caller) private view {
        if (!_isRegistered(vault)) revert VaultNotRegistered(vault);
        if (!isController(vault, caller)) revert NotController(vault, caller);
    }

    function _requireVaultNotPaused(address vault) private view {
        if (IVault(vault).paused()) revert VaultIsPaused(vault);
    }

    function _isRegistered(address vault) private view returns (bool) {
        return _vaultRecords[vault].controller != address(0);
    }

    function _onlyConfigured() private view {
        if (!configured) revert NotConfigured();
    }

    function _requireComponentType(address target, bytes32 expected, bytes32 component) private view {
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

    function _onlyAdminController() private view {
        if (msg.sender != adminController) revert NotAdminController(msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        _requireComponentType(newImplementation, ComponentTypes.GRANTLINE, bytes32("grantline.implementation"));
    }
}
