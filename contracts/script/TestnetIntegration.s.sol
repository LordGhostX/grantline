// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ComponentTypes} from "../src/ComponentTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {DeploymentManifest} from "./DeploymentManifest.s.sol";
import {VerifyGrantlineDeployment} from "./VerifyGrantlineDeployment.s.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

interface TestnetIntegrationVm {
    function envAddress(string calldata name) external returns (address value);

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);

    function expectRevert() external;

    function prank(address sender) external;

    function toString(uint256 value) external pure returns (string memory);

    function toString(address value) external pure returns (string memory);

    function toString(bytes32 value) external pure returns (string memory);
}

contract IntegrationToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if (balanceOf[sender] < amount || allowance[sender][msg.sender] < amount) return false;
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract RejectingRecipient {
    receive() external payable {
        revert();
    }
}

contract ReentrantRecipient {
    address public target;
    bytes public callData;
    bool public attempted;
    bool public callSucceeded;

    function configure(address target_, bytes calldata callData_) external {
        target = target_;
        callData = callData_;
        attempted = false;
        callSucceeded = false;
    }

    receive() external payable {
        if (attempted) return;
        attempted = true;
        (callSucceeded,) = target.call(callData);
    }
}

contract VaultV2 is Vault {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract HookRecipient {
    receive() external payable { }
}

contract MandateRegistryV2 is MandateRegistry {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract TestnetIntegration is ScriptBase {
    uint256 internal constant DEPOSIT_AMOUNT = 0.05 ether;
    uint256 internal constant SECOND_VAULT_DEPOSIT = 0.002 ether;
    uint256 internal constant ROOT_TRANSACTION_LIMIT = 0.001 ether;
    uint256 internal constant ESCALATED_AMOUNT = 0.002 ether;
    uint256 internal constant CHILD_TRANSACTION_LIMIT = 0.0005 ether;
    uint256 internal constant GRANDCHILD_TRANSACTION_LIMIT = 0.0003 ether;
    uint256 internal constant ROOT_TIGHTENED_LIMIT = 0.0004 ether;
    uint256 internal constant ROOT_PREFLIGHT_FLOOR = 0.04 ether;
    uint256 internal constant TIGHTENED_PREFLIGHT_FLOOR = 0.049 ether;
    uint256 internal constant TOKEN_DEPOSIT = 1_000 ether;
    uint256 internal constant TOKEN_TRANSFER = 300 ether;

    uint256 internal constant ROOT_ALLOW_NONCE = 1;
    uint256 internal constant ROOT_DENY_NONCE = 2;
    uint256 internal constant ROOT_ATOMIC_NONCE = 3;
    uint256 internal constant ROOT_REENTRANCY_NONCE = 4;
    uint256 internal constant ROOT_ESCALATION_NONCE = 5;
    uint256 internal constant ROOT_TOKEN_NONCE = 6;
    uint256 internal constant ROOT_REVOKED_ESCALATION_NONCE = 7;
    uint256 internal constant ROOT_CANCELLED_NONCE = 8;
    uint256 internal constant ROOT_HOOK_NONCE = 9;
    uint256 internal constant ROOT_MIN_AMOUNT_NONCE = 10;
    uint256 internal constant ROOT_VALIDITY_NONCE = 11;
    uint256 internal constant ROOT_RESERVATION_NONCE = 12;
    uint256 internal constant CHILD_ALLOW_NONCE = 1;
    uint256 internal constant CHILD_ESCALATION_NONCE = 2;
    uint256 internal constant CHILD_CONTROLLER_CANCEL_NONCE = 3;
    uint256 internal constant GRANDCHILD_ALLOW_NONCE = 1;
    uint256 internal constant REENTRY_NONCE = 90;
    uint256 internal constant CHILD_TOKEN_EVALUATION_NONCE = 50;

    address internal constant SUCCESS_RECIPIENT = address(0x1001);
    address internal constant TOKEN_RECIPIENT = address(0x1002);
    address internal constant ATOMIC_RECIPIENT = address(0x1003);
    address internal constant ESCALATION_RECIPIENT = address(0x1004);
    address internal constant CHILD_RECIPIENT = address(0x1005);
    address internal constant GRANDCHILD_RECIPIENT = address(0x1006);
    address internal constant PENDING_RECIPIENT = address(0x1007);
    address internal constant CANCELLED_RECIPIENT = address(0x1008);
    address internal constant HOOK_RECIPIENT = address(0x1009);
    address internal constant MIN_AMOUNT_RECIPIENT = address(0x100A);

    TestnetIntegrationVm private constant integrationVm =
        TestnetIntegrationVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    error AgentKeyMismatch(address expectedAgent, address actualAgent);
    error IntegrationInvariant(string check);

    event IntegrationCompleted(
        address indexed grantline,
        address indexed vault,
        address indexed secondVault,
        address thirdVault,
        uint256 rootMandate,
        uint256 childMandate,
        uint256 grandchildMandate,
        bytes32 rootEscalation,
        bytes32 childEscalation,
        bytes32 deniedEscalation
    );

    struct State {
        string network;
        uint256 expectedChainId;
        address hub;
        address hubImplementation;
        address admin;
        address registry;
        address registryImplementation;
        address evaluator;
        address evaluatorImplementation;
        address escalationManager;
        address escalationManagerImplementation;
        address executor;
        address executorImplementation;
        address vaultFactory;
        address vaultFactoryImplementation;
        address initialVaultImplementation;
        address uniswapV3SwapAdapter;
        address uniswapV3Router;
        address uniswapV3Factory;
        address wrappedNative;
        bool nativeUsdEnabled;
        address chainlinkNativeUsdFeed;
        uint8 chainlinkNativeUsdFeedDecimals;
        uint256 ownerKey;
        uint256 agentKey;
        uint256 delegatedKey;
        address owner;
        address agent;
        address delegatedAgent;
        address expectedProtocolAdmin;
        address vault;
        address secondVault;
        address thirdVault;
        address token;
        address rejectingRecipient;
        address reentrantRecipient;
        address hookRecipient;
        address vaultV2;
        address registryV2;
        uint256 rootMandate;
        uint256 childMandate;
        uint256 grandchildMandate;
        bytes32 rootEscalation;
        bytes32 childEscalation;
        bytes32 deniedEscalation;
    }

    function run() external {
        State memory state = _loadState();
        _validateStack(state);
        state = _createVaults(state);
        state = _deployFixtures(state);
        state = _fundVaultsAndCreateRoot(state);
        _assertControllerIsolationAndBypasses(state);
        state = _runNativeExecutionAndEscalation(state);
        state = _runTokenExecution(state);
        state = _runVaultAndMandatePausing(state);
        state = _runDelegationAndPreflight(state);
        state = _runValidityWindows(state);
        state = _runControllerCancellation(state);
        state = _runMinAmount(state);
        state = _runUpgrades(state);
        _runRevocationAndReservationChecks(state);
        _cleanupVaults(state);
        _verifyFinalDeployment(state);

        emit IntegrationCompleted(
            state.hub,
            state.vault,
            state.secondVault,
            state.thirdVault,
            state.rootMandate,
            state.childMandate,
            state.grandchildMandate,
            state.rootEscalation,
            state.childEscalation,
            state.deniedEscalation
        );
    }

    function _loadState() private returns (State memory state) {
        string memory manifest = _manifest();
        state.network = vm.parseJsonString(manifest, ".network");
        state.expectedChainId = vm.parseJsonUint(manifest, ".chainId");
        state.expectedProtocolAdmin = vm.parseJsonAddress(manifest, ".grantline.protocolAdmin");
        state.admin = vm.parseJsonAddress(manifest, ".admin.address");
        state.hub = vm.parseJsonAddress(manifest, ".grantline.proxy");
        state.hubImplementation = vm.parseJsonAddress(manifest, ".grantline.implementation");
        state.registry = vm.parseJsonAddress(manifest, ".modules.registry.proxy");
        state.registryImplementation = vm.parseJsonAddress(manifest, ".modules.registry.implementation");
        state.evaluator = vm.parseJsonAddress(manifest, ".modules.evaluator.proxy");
        state.evaluatorImplementation = vm.parseJsonAddress(manifest, ".modules.evaluator.implementation");
        state.escalationManager = vm.parseJsonAddress(manifest, ".modules.escalationManager.proxy");
        state.escalationManagerImplementation =
            vm.parseJsonAddress(manifest, ".modules.escalationManager.implementation");
        state.executor = vm.parseJsonAddress(manifest, ".modules.executor.proxy");
        state.executorImplementation = vm.parseJsonAddress(manifest, ".modules.executor.implementation");
        state.vaultFactory = vm.parseJsonAddress(manifest, ".modules.vaultFactory.proxy");
        state.vaultFactoryImplementation = vm.parseJsonAddress(manifest, ".modules.vaultFactory.implementation");
        state.initialVaultImplementation = vm.parseJsonAddress(manifest, ".vaultImplementation.address");
        state.uniswapV3SwapAdapter = vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.swapAdapter");
        state.uniswapV3Router = vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.router");
        state.uniswapV3Factory = vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.factory");
        state.wrappedNative = vm.parseJsonAddress(manifest, ".nativeAsset.wrappedNative");
        (state.nativeUsdEnabled, state.chainlinkNativeUsdFeed, state.chainlinkNativeUsdFeedDecimals) =
            _loadNativeUsdManifest(manifest);

        state.ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        state.agentKey = vm.envUint("AGENT_PRIVATE_KEY");
        state.delegatedKey = vm.envUint("DELEGATED_AGENT_PRIVATE_KEY");
        state.owner = vm.addr(state.ownerKey);
        state.agent = vm.addr(state.agentKey);
        state.delegatedAgent = vm.addr(state.delegatedKey);

        _requireAgentAddress(state.agent, integrationVm.envAddress("AGENT_PUBLIC_KEY"));
        _requireAgentAddress(state.delegatedAgent, integrationVm.envAddress("DELEGATED_AGENT_PUBLIC_KEY"));
    }

    function _loadNativeUsdManifest(string memory manifest)
        internal
        returns (bool enabled, address feed, uint8 decimals)
    {
        enabled = vm.parseJsonBool(manifest, ".nativeAsset.chainlinkUsdFeed.enabled");
        feed = vm.parseJsonAddress(manifest, ".nativeAsset.chainlinkUsdFeed.feed");
        decimals = SafeCast.toUint8(vm.parseJsonUint(manifest, ".nativeAsset.chainlinkUsdFeed.decimals"));
        _validateNativeUsdManifest(enabled, feed, decimals);
    }

    function _validateNativeUsdManifest(bool enabled, address feed, uint8 decimals) internal pure {
        _require(enabled == (feed != address(0)), "native USD manifest enablement mismatch");
        _require(enabled || decimals == 0, "native USD manifest decimals mismatch");
    }

    function _validateStack(State memory state) private view {
        Grantline hub = Grantline(state.hub);
        _require(block.chainid == state.expectedChainId, "manifest chain ID does not match RPC chain");
        _require(hub.owner() == state.owner, "protocol admin does not match deployer");
        _require(hub.owner() == state.expectedProtocolAdmin, "manifest protocol admin mismatch");
        _require(hub.adminController() == state.admin, "admin controller mismatch");
        _require(GrantlineAdmin(state.admin).grantline() == state.hub, "admin Grantline mismatch");
        _require(hub.configured(), "Grantline is not configured");
        _require(hub.registry() == state.registry, "registry proxy mismatch");
        _require(hub.evaluator() == state.evaluator, "evaluator proxy mismatch");
        _require(hub.escalationManager() == state.escalationManager, "escalation manager proxy mismatch");
        _require(hub.executor() == state.executor, "executor proxy mismatch");
        _require(hub.vaultFactory() == state.vaultFactory, "Vault factory proxy mismatch");
        (bool nativeUsdEnabled, address nativeUsdFeed, uint8 nativeUsdDecimals, address wrappedNativeAddress) =
            hub.getNativeUsdValuation();
        _require(nativeUsdEnabled == state.nativeUsdEnabled, "native USD enablement mismatch");
        _require(nativeUsdFeed == state.chainlinkNativeUsdFeed, "native USD feed mismatch");
        _require(nativeUsdDecimals == state.chainlinkNativeUsdFeedDecimals, "native USD decimals mismatch");
        _require(wrappedNativeAddress == state.wrappedNative, "wrapped native mismatch");
        _require(hub.vaultCount() == 0, "integration requires a fresh Grantline deployment");

        _require(hub.componentType() == ComponentTypes.GRANTLINE, "Grantline component type mismatch");

        _require(MandateRegistry(state.registry).grantline() == state.hub, "registry Grantline mismatch");
        _require(MandateEvaluator(state.evaluator).grantline() == state.hub, "evaluator Grantline mismatch");
        _require(EscalationManager(state.escalationManager).grantline() == state.hub, "manager Grantline mismatch");
        _require(VaultExecutor(state.executor).grantline() == state.hub, "executor Grantline mismatch");
        _require(VaultFactory(state.vaultFactory).grantline() == state.hub, "factory Grantline mismatch");
        _require(
            MandateRegistry(state.registry).componentType() == ComponentTypes.REGISTRY,
            "registry component type mismatch"
        );
        _require(
            MandateEvaluator(state.evaluator).componentType() == ComponentTypes.EVALUATOR,
            "evaluator component type mismatch"
        );
        _require(
            EscalationManager(state.escalationManager).componentType() == ComponentTypes.ESCALATION_MANAGER,
            "manager component type mismatch"
        );
        _require(
            VaultExecutor(state.executor).componentType() == ComponentTypes.EXECUTOR, "executor component type mismatch"
        );
        _require(
            VaultFactory(state.vaultFactory).componentType() == ComponentTypes.VAULT_FACTORY,
            "factory component type mismatch"
        );
        _require(MandateEvaluator(state.evaluator).registry() == state.registry, "evaluator registry mismatch");
        _require(EscalationManager(state.escalationManager).registry() == state.registry, "manager registry mismatch");
        _require(VaultExecutor(state.executor).registry() == state.registry, "executor registry mismatch");
        _require(
            EscalationManager(state.escalationManager).evaluator() == state.evaluator, "manager evaluator mismatch"
        );
        _require(VaultExecutor(state.executor).evaluator() == state.evaluator, "executor evaluator mismatch");
        _require(
            VaultExecutor(state.executor).escalationManager() == state.escalationManager, "executor manager mismatch"
        );
        _require(VaultFactory(state.vaultFactory).executor() == state.executor, "factory executor mismatch");
        _require(VaultFactory(state.vaultFactory).vaultCount() == 0, "factory is not fresh");
    }

    function _createVaults(State memory state) private returns (State memory) {
        vm.startBroadcast(state.ownerKey);
        state.vault = Grantline(state.hub).createVault();
        vm.stopBroadcast();

        vm.startBroadcast(state.delegatedKey);
        state.secondVault = Grantline(state.hub).createVault();
        vm.stopBroadcast();

        _require(Grantline(state.hub).controllerOf(state.vault) == state.owner, "first Vault controller mismatch");
        _require(
            Grantline(state.hub).controllerOf(state.secondVault) == state.delegatedAgent,
            "second Vault controller mismatch"
        );
        _require(Vault(payable(state.vault)).grantline() == state.hub, "first Vault Grantline mismatch");
        _require(Vault(payable(state.secondVault)).grantline() == state.hub, "second Vault Grantline mismatch");
        _require(Vault(payable(state.vault)).owner() == state.hub, "first Vault owner bypass is possible");
        _require(Vault(payable(state.secondVault)).owner() == state.hub, "second Vault owner mismatch");
        _require(Vault(payable(state.vault)).authority() == state.executor, "first Vault authority mismatch");
        _require(Vault(payable(state.secondVault)).authority() == state.executor, "second Vault authority mismatch");
        _require(!Vault(payable(state.vault)).paused(), "first Vault is unexpectedly paused");
        _require(!Vault(payable(state.secondVault)).paused(), "second Vault is unexpectedly paused");
        _assertVaultIndexes(state);
        return state;
    }

    function _deployFixtures(State memory state) private returns (State memory) {
        vm.startBroadcast(state.ownerKey);
        state.token = address(new IntegrationToken());
        IntegrationToken(state.token).mint(state.owner, TOKEN_DEPOSIT);
        state.rejectingRecipient = address(new RejectingRecipient());
        state.reentrantRecipient = address(new ReentrantRecipient());
        state.hookRecipient = address(new HookRecipient());
        state.vaultV2 = address(new VaultV2());
        state.registryV2 = address(new MandateRegistryV2());
        vm.stopBroadcast();
        return state;
    }

    function _fundVaultsAndCreateRoot(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);
        GrantlineTypes.MandateRules memory rootRules = _rules(ROOT_TRANSACTION_LIMIT, true, true);
        GrantlineTypes.PreflightRules memory rootPreflight = _preflight(ROOT_PREFLIGHT_FLOOR, true);

        vm.startBroadcast(state.delegatedKey);
        hub.depositNative{value: SECOND_VAULT_DEPOSIT}(state.secondVault);
        vm.stopBroadcast();

        vm.startBroadcast(state.ownerKey);
        hub.depositNative{value: DEPOSIT_AMOUNT}(state.vault);
        state.rootMandate = hub.createMandate(state.vault, state.agent, rootRules, rootPreflight, 0, 0);
        IntegrationToken(state.token).approve(state.vault, TOKEN_DEPOSIT);
        hub.depositToken(state.vault, state.token, TOKEN_DEPOSIT);
        vm.stopBroadcast();

        _require(address(state.vault).balance == DEPOSIT_AMOUNT, "first Vault native deposit mismatch");
        _require(address(state.secondVault).balance == SECOND_VAULT_DEPOSIT, "second Vault native deposit mismatch");
        _require(IntegrationToken(state.token).balanceOf(state.vault) == TOKEN_DEPOSIT, "token deposit mismatch");
        MandateRegistry registry = MandateRegistry(state.registry);
        GrantlineTypes.Mandate memory root = registry.getMandate(state.rootMandate);
        _require(root.agent == state.agent, "root agent mismatch");
        _require(root.createdBy == state.owner, "root mandate creator mismatch");
        _require(registry.vaultMandateCount(state.vault) == 1, "root Vault Mandate index count mismatch");
        _require(registry.vaultMandateAt(state.vault, 0) == state.rootMandate, "root Vault Mandate index mismatch");
        _require(registry.creatorMandateCount(state.owner) == 1, "root creator Mandate index count mismatch");
        _require(registry.creatorMandateAt(state.owner, 0) == state.rootMandate, "root creator Mandate index mismatch");
        _require(registry.agentMandateCount(state.agent) == 1, "root agent Mandate index count mismatch");
        _require(registry.agentMandateAt(state.agent, 0) == state.rootMandate, "root agent Mandate index mismatch");
        return state;
    }

    function _assertControllerIsolationAndBypasses(State memory state) private {
        Grantline hub = Grantline(state.hub);
        GrantlineTypes.MandateRules memory rules = _rules(ROOT_TRANSACTION_LIMIT, false, false);
        GrantlineTypes.PreflightRules memory preflight = _preflight(0, false);

        integrationVm.prank(state.owner);
        integrationVm.expectRevert();
        hub.withdrawNative(state.secondVault, payable(state.owner), 1);

        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.createMandate(state.secondVault, state.agent, rules, preflight, 0, 0);

        ActionTypes.ActionPlan memory probe = _nativePlan(state.rootMandate, state.agent, 70, 1, SUCCESS_RECIPIENT, 0);
        bytes32 digest = hub.actionDigest(probe);

        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        GrantlineAdmin(state.admin).setVaultController(state.secondVault, state.agent);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        MandateEvaluator(state.evaluator).evaluate(probe, bytes(""), digest, false);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        EscalationManager(state.escalationManager).submit(probe, bytes(""), digest, state.agent);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        VaultExecutor(state.executor).execute(probe, bytes(""), digest);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        MandateRegistry(state.registry).revokeMandate(state.rootMandate, state.agent);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        VaultFactory(state.vaultFactory).createVault(state.agent);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        Vault(payable(state.vault)).withdrawNative(payable(state.agent), 1);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        Vault(payable(state.vault)).execute(SUCCESS_RECIPIENT, 0, bytes(""));
    }

    function _runNativeExecutionAndEscalation(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);

        ActionTypes.ActionPlan memory allowPlan =
            _nativePlan(state.rootMandate, state.agent, ROOT_ALLOW_NONCE, 0.001 ether, SUCCESS_RECIPIENT, 0);
        bytes memory allowSignature = _sign(state, allowPlan, state.agentKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(allowPlan, allowSignature);
        _require(evaluation.decision == 0, "normal plan was not ALLOW");
        uint256 recipientBalance = SUCCESS_RECIPIENT.balance;
        vm.startBroadcast(state.delegatedKey);
        hub.execute(allowPlan, allowSignature);
        vm.stopBroadcast();
        _require(SUCCESS_RECIPIENT.balance == recipientBalance + 0.001 ether, "normal transfer mismatch");
        _require(
            MandateRegistry(state.registry).nonceUsed(state.rootMandate, state.agent, ROOT_ALLOW_NONCE),
            "normal nonce not consumed"
        );

        ActionTypes.ActionPlan memory cancelledPlan =
            _nativePlan(state.rootMandate, state.agent, ROOT_CANCELLED_NONCE, 0.0001 ether, CANCELLED_RECIPIENT, 0);
        bytes memory cancelledSignature = _sign(state, cancelledPlan, state.agentKey);
        evaluation = hub.evaluate(cancelledPlan, cancelledSignature);
        _require(evaluation.decision == 0, "cancellation plan was not initially ALLOW");
        vm.startBroadcast(state.agentKey);
        hub.cancelNonce(state.rootMandate, ROOT_CANCELLED_NONCE);
        vm.stopBroadcast();
        (bool cancelled, bytes32 cancelledReservation) = hub.getNonceState(state.rootMandate, ROOT_CANCELLED_NONCE);
        _require(cancelled, "cancelled nonce remained available");
        _require(cancelledReservation == bytes32(0), "cancelled nonce gained a reservation");
        uint256 cancelledRecipientBalance = CANCELLED_RECIPIENT.balance;
        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.execute(cancelledPlan, cancelledSignature);
        _require(CANCELLED_RECIPIENT.balance == cancelledRecipientBalance, "cancelled plan moved funds");

        ActionTypes.ActionPlan memory deniedPlan =
            _nativePlan(state.rootMandate, state.agent, ROOT_DENY_NONCE, 1, SUCCESS_RECIPIENT, 0);
        evaluation = hub.evaluate(deniedPlan, bytes(""));
        _require(evaluation.decision == 2, "invalid signature was not DENY");
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.execute(deniedPlan, bytes(""));
        _require(
            !MandateRegistry(state.registry).nonceUsed(state.rootMandate, state.agent, ROOT_DENY_NONCE),
            "denied nonce was consumed"
        );

        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.execute(allowPlan, allowSignature);

        ActionTypes.ActionPlan memory atomicPlan = _twoActionNativePlan(
            state.rootMandate,
            state.agent,
            ROOT_ATOMIC_NONCE,
            ATOMIC_RECIPIENT,
            0.0001 ether,
            state.rejectingRecipient,
            1
        );
        bytes memory atomicSignature = _sign(state, atomicPlan, state.agentKey);
        evaluation = hub.evaluate(atomicPlan, atomicSignature);
        _require(evaluation.decision == 0, "atomic plan was not ALLOW");
        uint256 atomicBalance = ATOMIC_RECIPIENT.balance;
        uint256 vaultBalance = address(state.vault).balance;
        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.execute(atomicPlan, atomicSignature);
        _require(ATOMIC_RECIPIENT.balance == atomicBalance, "failed atomic plan moved the first action");
        _require(address(state.vault).balance == vaultBalance, "failed atomic plan changed Vault balance");
        _require(
            !MandateRegistry(state.registry).nonceUsed(state.rootMandate, state.agent, ROOT_ATOMIC_NONCE),
            "failed atomic plan consumed nonce"
        );

        ActionTypes.ActionPlan memory reentryPlan =
            _nativePlan(state.rootMandate, state.agent, REENTRY_NONCE, 1, SUCCESS_RECIPIENT, 0);
        bytes memory reentrySignature = _sign(state, reentryPlan, state.agentKey);
        bytes memory reentryCall = abi.encodeCall(Grantline.execute, (reentryPlan, reentrySignature));
        vm.startBroadcast(state.ownerKey);
        ReentrantRecipient(payable(state.reentrantRecipient)).configure(state.hub, reentryCall);
        vm.stopBroadcast();

        ActionTypes.ActionPlan memory reentrantPlan = _nativePlan(
            state.rootMandate, state.agent, ROOT_REENTRANCY_NONCE, 0.0001 ether, state.reentrantRecipient, 0
        );
        bytes memory reentrantSignature = _sign(state, reentrantPlan, state.agentKey);
        vm.startBroadcast(state.delegatedKey);
        hub.execute(reentrantPlan, reentrantSignature);
        vm.stopBroadcast();
        _require(
            ReentrantRecipient(payable(state.reentrantRecipient)).attempted(), "reentrant recipient was not called"
        );
        _require(
            !ReentrantRecipient(payable(state.reentrantRecipient)).callSucceeded(),
            "nested Grantline execution succeeded"
        );
        _require(
            !MandateRegistry(state.registry).nonceUsed(state.rootMandate, state.agent, REENTRY_NONCE),
            "nested execution consumed a nonce"
        );

        ActionTypes.ActionPlan memory hookPlan =
            _nativePlan(state.rootMandate, state.agent, ROOT_HOOK_NONCE, 0.0001 ether, HOOK_RECIPIENT, 0);
        bytes memory hookSignature = _sign(state, hookPlan, state.agentKey);
        evaluation = hub.evaluate(hookPlan, hookSignature);
        _require(evaluation.decision == 0, "hook plan was not ALLOW");
        uint256 hookBalance = HOOK_RECIPIENT.balance;
        vm.startBroadcast(state.delegatedKey);
        hub.execute(hookPlan, hookSignature);
        vm.stopBroadcast();
        _require(HOOK_RECIPIENT.balance == hookBalance + 0.0001 ether, "hook transfer mismatch");

        ActionTypes.ActionPlan memory escalationPlan = _nativePlan(
            state.rootMandate, state.agent, ROOT_ESCALATION_NONCE, ESCALATED_AMOUNT, ESCALATION_RECIPIENT, 0
        );
        bytes memory escalationSignature = _sign(state, escalationPlan, state.agentKey);
        evaluation = hub.evaluate(escalationPlan, escalationSignature);
        _require(evaluation.decision == 1, "over-limit plan was not ESCALATE");
        vm.startBroadcast(state.agentKey);
        state.rootEscalation = hub.submitEscalation(escalationPlan, escalationSignature);
        vm.stopBroadcast();
        _require(hub.escalationStatus(state.rootEscalation) == 1, "escalation was not pending");
        _require(hub.getEscalation(state.rootEscalation).submittedBy == state.agent, "escalation submitter mismatch");
        _assertEscalationIndexes(state, state.rootEscalation, state.agent, 1);

        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.execute(escalationPlan, escalationSignature);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.submitEscalation(escalationPlan, escalationSignature);

        ActionTypes.ActionPlan memory conflictingPlan =
            _nativePlan(state.rootMandate, state.agent, ROOT_ESCALATION_NONCE, 0.0021 ether, ESCALATION_RECIPIENT, 0);
        bytes memory conflictingSignature = _sign(state, conflictingPlan, state.agentKey);
        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.submitEscalation(conflictingPlan, conflictingSignature);

        vm.startBroadcast(state.ownerKey);
        hub.approveEscalation(state.rootEscalation);
        vm.stopBroadcast();
        _require(hub.escalationStatus(state.rootEscalation) == 2, "escalation was not approved");
        uint256 escalationBalance = ESCALATION_RECIPIENT.balance;
        vm.startBroadcast(state.delegatedKey);
        hub.executeEscalated(state.rootEscalation);
        vm.stopBroadcast();
        _require(ESCALATION_RECIPIENT.balance == escalationBalance + ESCALATED_AMOUNT, "escalated transfer mismatch");
        _require(hub.escalationStatus(state.rootEscalation) == 4, "escalation was not executed");
        _require(
            MandateRegistry(state.registry).nonceUsed(state.rootMandate, state.agent, ROOT_ESCALATION_NONCE),
            "escalated nonce not consumed"
        );
        _assertEscalationIndexes(state, state.rootEscalation, state.agent, 1);
        return state;
    }

    function _runTokenExecution(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);
        ActionTypes.ActionPlan memory tokenPlan = _assetPlan(
            state.rootMandate, state.agent, ROOT_TOKEN_NONCE, TOKEN_TRANSFER, state.token, TOKEN_RECIPIENT, 0
        );
        bytes memory tokenSignature = _sign(state, tokenPlan, state.agentKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(tokenPlan, tokenSignature);
        _require(evaluation.decision == 0, "token plan was not ALLOW");
        _require(evaluation.nativeAmount == 0, "token plan reported native value");
        vm.startBroadcast(state.agentKey);
        hub.execute(tokenPlan, tokenSignature);
        vm.stopBroadcast();
        _require(IntegrationToken(state.token).balanceOf(TOKEN_RECIPIENT) == TOKEN_TRANSFER, "token transfer mismatch");
        _require(
            IntegrationToken(state.token).balanceOf(state.vault) == TOKEN_DEPOSIT - TOKEN_TRANSFER,
            "Vault token balance mismatch"
        );
        return state;
    }

    function _runVaultAndMandatePausing(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);

        vm.startBroadcast(state.ownerKey);
        hub.pauseVault(state.vault);
        vm.stopBroadcast();
        _require(Vault(payable(state.vault)).paused(), "vault was not paused");

        ActionTypes.ActionPlan memory pausedPlan =
            _nativePlan(state.rootMandate, state.agent, 99, 0.0001 ether, SUCCESS_RECIPIENT, 0);
        bytes memory pausedSignature = _sign(state, pausedPlan, state.agentKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(pausedPlan, pausedSignature);
        _require(evaluation.decision == 2, "paused vault plan was not DENY");
        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.execute(pausedPlan, pausedSignature);

        vm.startBroadcast(state.ownerKey);
        hub.unpauseVault(state.vault);
        vm.stopBroadcast();
        _require(!Vault(payable(state.vault)).paused(), "vault was not unpaused");

        vm.startBroadcast(state.ownerKey);
        hub.pauseMandate(state.rootMandate);
        vm.stopBroadcast();
        evaluation = hub.evaluate(pausedPlan, pausedSignature);
        _require(evaluation.decision == 2, "paused mandate plan was not DENY");

        vm.startBroadcast(state.ownerKey);
        hub.unpauseMandate(state.rootMandate);
        vm.stopBroadcast();

        return state;
    }

    function _runDelegationAndPreflight(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);
        GrantlineTypes.MandateRules memory childRules = _rules(CHILD_TRANSACTION_LIMIT, true, true);
        GrantlineTypes.PreflightRules memory childPreflight = _preflight(ROOT_PREFLIGHT_FLOOR, true);

        vm.startBroadcast(state.agentKey);
        state.childMandate =
            hub.createChildMandate(state.rootMandate, state.delegatedAgent, childRules, childPreflight, 0, 0);
        vm.stopBroadcast();
        _assertMandateIndexes(state, state.childMandate, state.agent, state.delegatedAgent, 2);

        vm.startBroadcast(state.agentKey);
        hub.updateMandate(state.childMandate, childRules, childPreflight, 0, 0);
        vm.stopBroadcast();

        ActionTypes.ActionPlan memory childPlan = _nativePlan(
            state.childMandate, state.delegatedAgent, CHILD_ALLOW_NONCE, CHILD_TRANSACTION_LIMIT, CHILD_RECIPIENT, 0
        );
        bytes memory childSignature = _sign(state, childPlan, state.delegatedKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(childPlan, childSignature);
        _require(evaluation.decision == 0, "child plan was not ALLOW");
        uint256 childBalance = CHILD_RECIPIENT.balance;
        vm.startBroadcast(state.delegatedKey);
        hub.execute(childPlan, childSignature);
        vm.stopBroadcast();
        _require(CHILD_RECIPIENT.balance == childBalance + CHILD_TRANSACTION_LIMIT, "child transfer mismatch");

        GrantlineTypes.MandateRules memory grandchildRules = _rules(GRANDCHILD_TRANSACTION_LIMIT, false, false);
        vm.startBroadcast(state.delegatedKey);
        state.grandchildMandate =
            hub.createChildMandate(state.childMandate, state.agent, grandchildRules, childPreflight, 0, 0);
        vm.stopBroadcast();
        _assertMandateIndexes(state, state.grandchildMandate, state.delegatedAgent, state.agent, 3);

        ActionTypes.ActionPlan memory grandchildPlan = _nativePlan(
            state.grandchildMandate,
            state.agent,
            GRANDCHILD_ALLOW_NONCE,
            GRANDCHILD_TRANSACTION_LIMIT,
            GRANDCHILD_RECIPIENT,
            0
        );
        bytes memory grandchildSignature = _sign(state, grandchildPlan, state.agentKey);
        evaluation = hub.evaluate(grandchildPlan, grandchildSignature);
        _require(evaluation.decision == 0, "grandchild plan was not ALLOW");
        uint256 grandchildBalance = GRANDCHILD_RECIPIENT.balance;
        vm.startBroadcast(state.agentKey);
        hub.execute(grandchildPlan, grandchildSignature);
        vm.stopBroadcast();
        _require(GRANDCHILD_RECIPIENT.balance == grandchildBalance + GRANDCHILD_TRANSACTION_LIMIT, "grandchild transfer mismatch");

        integrationVm.prank(state.agent);
        integrationVm.expectRevert();
        hub.createChildMandate(
            state.grandchildMandate, state.delegatedAgent, _rules(1, false, false), childPreflight, 0, 0
        );

        vm.startBroadcast(state.ownerKey);
        hub.updateMandate(
            state.rootMandate,
            _rules(ROOT_TIGHTENED_LIMIT, true, true),
            _preflight(TIGHTENED_PREFLIGHT_FLOOR, true),
            0,
            0
        );
        vm.stopBroadcast();

        GrantlineTypes.MandateRules memory effectiveChildRules = hub.getEffectiveRules(state.childMandate);
        GrantlineTypes.MandateRules memory effectiveGrandchildRules = hub.getEffectiveRules(state.grandchildMandate);
        GrantlineTypes.PreflightRules memory effectiveChildPreflight =
            hub.getEffectivePreflightRules(state.childMandate);
        _require(effectiveChildRules.maxNativeAmount == ROOT_TIGHTENED_LIMIT, "root tightening did not reach child");
        _require(
            effectiveGrandchildRules.maxNativeAmount == GRANDCHILD_TRANSACTION_LIMIT,
            "grandchild effective limit widened"
        );
        _require(
            effectiveChildPreflight.minNativeBalance == TIGHTENED_PREFLIGHT_FLOOR,
            "root Preflight tightening did not reach child"
        );

        ActionTypes.ActionPlan memory tokenOnlyPlan = _assetPlan(
            state.childMandate, state.delegatedAgent, CHILD_TOKEN_EVALUATION_NONCE, 1, state.token, TOKEN_RECIPIENT, 0
        );
        bytes memory tokenOnlySignature = _sign(state, tokenOnlyPlan, state.delegatedKey);
        evaluation = hub.evaluate(tokenOnlyPlan, tokenOnlySignature);
        _require(evaluation.decision == 1, "token-only Preflight breach was not ESCALATE");
        _require(evaluation.nativeAmount == 0, "token-only plan has native amount");

        ActionTypes.ActionPlan memory childEscalationPlan = _nativePlan(
            state.childMandate, state.delegatedAgent, CHILD_ESCALATION_NONCE, 0.0001 ether, CHILD_RECIPIENT, 0
        );
        bytes memory childEscalationSignature = _sign(state, childEscalationPlan, state.delegatedKey);
        evaluation = hub.evaluate(childEscalationPlan, childEscalationSignature);
        _require(evaluation.decision == 1, "child Preflight breach was not ESCALATE");
        vm.startBroadcast(state.delegatedKey);
        state.childEscalation = hub.submitEscalation(childEscalationPlan, childEscalationSignature);
        vm.stopBroadcast();
        vm.startBroadcast(state.ownerKey);
        hub.approveEscalation(state.childEscalation);
        hub.executeEscalated(state.childEscalation);
        vm.stopBroadcast();
        _require(hub.escalationStatus(state.childEscalation) == 4, "child escalation was not executed");
        _assertEscalationIndexes(state, state.childEscalation, state.delegatedAgent, 2);

        ActionTypes.ActionPlan memory pendingPlan = _nativePlan(
            state.rootMandate, state.agent, ROOT_REVOKED_ESCALATION_NONCE, 0.0005 ether, PENDING_RECIPIENT, 0
        );
        bytes memory pendingSignature = _sign(state, pendingPlan, state.agentKey);
        evaluation = hub.evaluate(pendingPlan, pendingSignature);
        _require(evaluation.decision == 1, "pending revoked plan was not ESCALATE");
        vm.startBroadcast(state.agentKey);
        state.deniedEscalation = hub.submitEscalation(pendingPlan, pendingSignature);
        vm.stopBroadcast();
        _require(hub.escalationStatus(state.deniedEscalation) == 1, "revocation fixture was not pending");
        _assertEscalationIndexes(state, state.deniedEscalation, state.agent, 3);
        return state;
    }

    function _runValidityWindows(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);

        GrantlineTypes.MandateRules memory validRules = _rules(ROOT_TRANSACTION_LIMIT, false, false);
        GrantlineTypes.PreflightRules memory validPreflight = _preflight(0, false);
        vm.startBroadcast(state.ownerKey);
        uint256 validityMandate = hub.createMandate(
            state.vault, state.agent, validRules, validPreflight, uint64(block.timestamp + 1 hours), 0
        );
        vm.stopBroadcast();
        (uint64 effectiveAfter,) = hub.getEffectiveValidityWindow(validityMandate);
        _require(effectiveAfter == uint64(block.timestamp + 1 hours), "validAfter mismatch");

        ActionTypes.ActionPlan memory futurePlan = _nativePlan(
            validityMandate, state.agent, ROOT_VALIDITY_NONCE, 0.0001 ether, SUCCESS_RECIPIENT, 0
        );
        bytes memory futureSignature = _sign(state, futurePlan, state.agentKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(futurePlan, futureSignature);
        _require(evaluation.decision == 2, "not-yet-valid mandate was not DENY");

        vm.startBroadcast(state.ownerKey);
        hub.revokeMandate(validityMandate);
        vm.stopBroadcast();

        vm.startBroadcast(state.ownerKey);
        uint256 expiryMandate = hub.createMandate(
            state.vault, state.agent, validRules, validPreflight, 0, uint64(block.timestamp - 1)
        );
        vm.stopBroadcast();
        evaluation = hub.evaluate(futurePlan, futureSignature);
        _require(evaluation.decision == 2, "expired mandate was not DENY");

        vm.startBroadcast(state.ownerKey);
        hub.revokeMandate(expiryMandate);
        vm.stopBroadcast();
        _require(
            MandateRegistry(state.registry).vaultMandateCount(state.vault) == 5,
            "validity Mandates were not retained in the Vault index"
        );
        return state;
    }

    function _runControllerCancellation(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);

        vm.startBroadcast(state.ownerKey);
        hub.cancelNonce(state.childMandate, CHILD_CONTROLLER_CANCEL_NONCE);
        vm.stopBroadcast();
        (bool cancelled, bytes32 reservation) = hub.getNonceState(state.childMandate, CHILD_CONTROLLER_CANCEL_NONCE);
        _require(cancelled, "controller cancelled nonce was not cancelled");
        _require(reservation == bytes32(0), "controller cancelled nonce gained reservation");

        ActionTypes.ActionPlan memory cancelledChildPlan = _nativePlan(
            state.childMandate, state.delegatedAgent, CHILD_CONTROLLER_CANCEL_NONCE, 0.0001 ether, CHILD_RECIPIENT, 0
        );
        bytes memory cancelledChildSignature = _sign(state, cancelledChildPlan, state.delegatedKey);
        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.execute(cancelledChildPlan, cancelledChildSignature);

        ActionTypes.ActionPlan memory reservationPlan = _nativePlan(
            state.rootMandate, state.agent, ROOT_RESERVATION_NONCE, 0.0001 ether, SUCCESS_RECIPIENT, 0
        );
        bytes memory reservationSignature = _sign(state, reservationPlan, state.agentKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(reservationPlan, reservationSignature);
        _require(evaluation.decision == 1, "reservation plan was not ESCALATE");
        vm.startBroadcast(state.agentKey);
        bytes32 reservationDigest = hub.submitEscalation(reservationPlan, reservationSignature);
        vm.stopBroadcast();
        _require(hub.escalationStatus(reservationDigest) == 1, "reservation escalation was not pending");
        _assertEscalationIndexes(state, reservationDigest, state.agent, 4);
        (bool reserved, bytes32 reservedReservation) =
            hub.getNonceState(state.rootMandate, ROOT_RESERVATION_NONCE);
        _require(!reserved, "reserved nonce appears used");
        _require(reservedReservation != bytes32(0), "reserved nonce has no reservation");
        evaluation = hub.evaluate(reservationPlan, reservationSignature);
        _require(evaluation.decision == 2, "reserved nonce plan was not DENY");
        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.execute(reservationPlan, reservationSignature);
        return state;
    }

    function _runMinAmount(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);

        GrantlineTypes.MandateRules memory minRules = GrantlineTypes.MandateRules({
            canDelegate: false,
            minNativeAmount: 0.0002 ether,
            maxNativeAmount: 0.001 ether,
            escalateNativeAmount: false,
            minNativeUsd: 0,
            maxNativeUsd: 0,
            escalateNativeUsd: false
        });
        GrantlineTypes.PreflightRules memory minPreflight = _preflight(0, false);
        vm.startBroadcast(state.ownerKey);
        uint256 minMandate = hub.createMandate(state.vault, state.agent, minRules, minPreflight, 0, 0);
        vm.stopBroadcast();

        ActionTypes.ActionPlan memory belowMinPlan = _nativePlan(
            minMandate, state.agent, ROOT_MIN_AMOUNT_NONCE, 0.0001 ether, MIN_AMOUNT_RECIPIENT, 0
        );
        bytes memory belowMinSignature = _sign(state, belowMinPlan, state.agentKey);
        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(belowMinPlan, belowMinSignature);
        _require(evaluation.decision == 2, "below-minimum plan was not DENY");

        vm.startBroadcast(state.ownerKey);
        hub.revokeMandate(minMandate);
        vm.stopBroadcast();
        return state;
    }

    function _runUpgrades(State memory state) private returns (State memory) {
        Grantline hub = Grantline(state.hub);
        Grantline.VaultView memory firstBefore = hub.getVault(state.vault);
        Grantline.VaultView memory secondBefore = hub.getVault(state.secondVault);

        vm.startBroadcast(state.ownerKey);
        GrantlineAdmin(state.admin).setVaultImplementation(state.vaultV2, 1);
        state.thirdVault = hub.createVault();
        GrantlineAdmin(state.admin).setVaultController(state.thirdVault, state.agent);
        vm.stopBroadcast();

        _require(hub.vaultCount() == 3, "Grantline Vault index count mismatch after upgrade fixture");
        _require(
            VaultFactory(state.vaultFactory).vaultCount() == 3,
            "factory Vault index count mismatch after upgrade fixture"
        );
        _require(hub.controllerVaultCount(state.owner) == 1, "owner Vault index changed after reassignment");
        _require(hub.controllerVaultAt(state.owner, 0) == state.vault, "owner Vault index points to the wrong Vault");
        _require(hub.controllerVaultCount(state.agent) == 1, "new controller Vault index count mismatch");
        _require(hub.controllerVaultAt(state.agent, 0) == state.thirdVault, "new controller Vault index mismatch");

        Grantline.VaultView memory thirdView = hub.getVault(state.thirdVault);
        _require(firstBefore.implementation == state.initialVaultImplementation, "first Vault changed with template");
        _require(secondBefore.implementation == state.initialVaultImplementation, "second Vault changed with template");
        _require(thirdView.implementation == state.vaultV2, "new Vault did not use new template");
        _require(thirdView.controller == state.agent, "Vault controller assignment failed");
        _require(VaultV2(payable(state.thirdVault)).marker() == 2, "new Vault implementation marker missing");

        uint256 nativeBalanceBefore = address(state.vault).balance;
        uint256 tokenBalanceBefore = IntegrationToken(state.token).balanceOf(state.vault);
        vm.startBroadcast(state.ownerKey);
        GrantlineAdmin(state.admin).upgradeVault(state.vault, state.vaultV2, 1, bytes(""));
        vm.stopBroadcast();
        _require(VaultV2(payable(state.vault)).marker() == 2, "existing Vault upgrade did not apply");
        _require(address(state.vault).balance == nativeBalanceBefore, "Vault upgrade changed native balance");
        _require(
            IntegrationToken(state.token).balanceOf(state.vault) == tokenBalanceBefore,
            "Vault upgrade changed token balance"
        );
        _require(hub.getVault(state.vault).implementation == state.vaultV2, "Vault implementation metadata not updated");
        _require(
            hub.getVault(state.secondVault).implementation == state.initialVaultImplementation,
            "other Vault upgraded unexpectedly"
        );

        address secondImplementation = hub.getVault(state.secondVault).implementation;
        integrationVm.prank(state.owner);
        integrationVm.expectRevert();
        GrantlineAdmin(state.admin).upgradeVault(state.secondVault, state.vaultV2, 2, bytes(""));
        _require(
            hub.getVault(state.secondVault).implementation == secondImplementation,
            "failed Vault upgrade changed metadata"
        );

        vm.startBroadcast(state.delegatedKey);
        hub.pauseVault(state.secondVault);
        vm.stopBroadcast();
        vm.startBroadcast(state.ownerKey);
        GrantlineAdmin(state.admin).upgradeVault(state.secondVault, state.vaultV2, 1, bytes(""));
        vm.stopBroadcast();
        _require(Vault(payable(state.secondVault)).paused(), "vault upgrade lost pause state");
        _require(VaultV2(payable(state.secondVault)).marker() == 2, "paused vault upgrade did not apply");
        vm.startBroadcast(state.delegatedKey);
        hub.unpauseVault(state.secondVault);
        vm.stopBroadcast();
        _require(!Vault(payable(state.secondVault)).paused(), "vault unpause after upgrade failed");

        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: hub.REGISTRY_MODULE(), implementation: state.registryV2, version: 1, data: bytes("")
        });
        uint256 mandateCountBefore = MandateRegistry(state.registry).mandateCount();
        vm.startBroadcast(state.ownerKey);
        GrantlineAdmin(state.admin).upgradeModules(upgrades);
        vm.stopBroadcast();
        state.registryImplementation = state.registryV2;
        _require(MandateRegistryV2(state.registry).marker() == 2, "registry module upgrade did not apply");
        _require(
            MandateRegistry(state.registry).mandateCount() == mandateCountBefore, "registry state was lost on upgrade"
        );
        _require(
            MandateRegistry(state.registry).isRegisteredVault(state.vault), "registry Vault state was lost on upgrade"
        );
        return state;
    }

    function _runRevocationAndReservationChecks(State memory state) private {
        Grantline hub = Grantline(state.hub);
        ActionTypes.ActionPlan memory pendingPlan = _nativePlan(
            state.rootMandate, state.agent, ROOT_REVOKED_ESCALATION_NONCE, 0.0005 ether, PENDING_RECIPIENT, 0
        );
        bytes memory pendingSignature = _sign(state, pendingPlan, state.agentKey);

        vm.startBroadcast(state.ownerKey);
        hub.revokeMandate(state.rootMandate);
        vm.stopBroadcast();
        integrationVm.prank(state.owner);
        integrationVm.expectRevert();
        hub.approveEscalation(state.deniedEscalation);
        vm.startBroadcast(state.ownerKey);
        hub.denyEscalation(state.deniedEscalation);
        vm.stopBroadcast();

        _require(hub.escalationStatus(state.deniedEscalation) == 3, "revoked escalation was not denied");
        _require(
            MandateRegistry(state.registry)
                    .reservedDigest(state.rootMandate, state.agent, ROOT_REVOKED_ESCALATION_NONCE)
                == state.deniedEscalation,
            "denied escalation reservation was released"
        );
        _assertEscalationIndexes(state, state.deniedEscalation, state.agent, 4);

        GrantlineTypes.EvaluationResult memory evaluation = hub.evaluate(pendingPlan, pendingSignature);
        _require(evaluation.decision == 2, "revoked root plan was not DENY");
        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.execute(pendingPlan, pendingSignature);

        ActionTypes.ActionPlan memory childPlan = _nativePlan(
            state.childMandate, state.delegatedAgent, CHILD_ALLOW_NONCE, CHILD_TRANSACTION_LIMIT, CHILD_RECIPIENT, 0
        );
        bytes memory childSignature = _sign(state, childPlan, state.delegatedKey);
        evaluation = hub.evaluate(childPlan, childSignature);
        _require(evaluation.decision == 2, "revoked ancestor did not DENY child plan");
        _require(
            !MandateRegistry(state.registry).isLineageActive(state.childMandate), "revoked child lineage remains active"
        );
        _require(
            !MandateRegistry(state.registry).isLineageActive(state.grandchildMandate),
            "revoked grandchild lineage remains active"
        );

        integrationVm.prank(state.delegatedAgent);
        integrationVm.expectRevert();
        hub.revokeMandate(state.grandchildMandate);
    }

    function _cleanupVaults(State memory state) private {
        Grantline hub = Grantline(state.hub);
        uint256 nativeBalance = address(state.vault).balance;
        uint256 tokenBalance = IntegrationToken(state.token).balanceOf(state.vault);
        vm.startBroadcast(state.ownerKey);
        hub.withdrawNative(state.vault, payable(state.owner), nativeBalance);
        hub.withdrawToken(state.vault, state.token, state.owner, tokenBalance);
        vm.stopBroadcast();

        uint256 secondBalance = address(state.secondVault).balance;
        vm.startBroadcast(state.delegatedKey);
        hub.withdrawNative(state.secondVault, payable(state.delegatedAgent), secondBalance);
        vm.stopBroadcast();

        _require(address(state.vault).balance == 0, "first Vault cleanup failed");
        _require(address(state.secondVault).balance == 0, "second Vault cleanup failed");
        _require(IntegrationToken(state.token).balanceOf(state.vault) == 0, "token cleanup failed");
    }

    function _verifyFinalDeployment(State memory state) private {
        string memory manifest = _verificationManifest(state);
        vm.writeJson(manifest, _manifestPath());
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        verifier.runWithManifest(manifest);
    }

    function _verificationManifest(State memory state) internal view returns (string memory) {
        DeploymentManifest.Snapshot memory snapshot;
        snapshot.network = state.network;
        snapshot.chainId = block.chainid;
        snapshot.grantline = state.hub;
        snapshot.grantlineImplementation = state.hubImplementation;
        snapshot.grantlineProxyCodeHash = state.hub.codehash;
        snapshot.protocolAdmin = state.owner;
        snapshot.admin = state.admin;
        snapshot.uniswapV3SwapAdapter = state.uniswapV3SwapAdapter;
        snapshot.uniswapV3Router = state.uniswapV3Router;
        snapshot.uniswapV3Factory = state.uniswapV3Factory;
        snapshot.wrappedNative = state.wrappedNative;
        snapshot.chainlinkNativeUsdFeed = state.chainlinkNativeUsdFeed;
        snapshot.chainlinkNativeUsdFeedDecimals = state.chainlinkNativeUsdFeedDecimals;
        snapshot.modules[0] = DeploymentManifest.ModuleSnapshot(state.registry, state.registryImplementation);
        snapshot.modules[1] = DeploymentManifest.ModuleSnapshot(state.evaluator, state.evaluatorImplementation);
        snapshot.modules[2] =
            DeploymentManifest.ModuleSnapshot(state.escalationManager, state.escalationManagerImplementation);
        snapshot.modules[3] = DeploymentManifest.ModuleSnapshot(state.executor, state.executorImplementation);
        snapshot.modules[4] = DeploymentManifest.ModuleSnapshot(state.vaultFactory, state.vaultFactoryImplementation);
        return DeploymentManifest.build(snapshot);
    }

    function _assertVaultIndexes(State memory state) private view {
        Grantline hub = Grantline(state.hub);
        VaultFactory factory = VaultFactory(state.vaultFactory);
        _require(hub.vaultCount() == 2, "Grantline Vault index count mismatch");
        _require(factory.vaultCount() == 2, "factory Vault index count mismatch");
        _require(hub.isRegisteredVault(state.vault), "first Vault was not registered");
        _require(hub.isRegisteredVault(state.secondVault), "second Vault was not registered");
        _require(hub.controllerVaultCount(state.owner) == 1, "owner Vault index count mismatch");
        _require(hub.controllerVaultAt(state.owner, 0) == state.vault, "owner Vault index mismatch");
        _require(hub.controllerVaultCount(state.delegatedAgent) == 1, "delegated controller Vault index count mismatch");
        _require(
            hub.controllerVaultAt(state.delegatedAgent, 0) == state.secondVault,
            "delegated controller Vault index mismatch"
        );
    }

    function _assertMandateIndexes(
        State memory state,
        uint256 mandateId,
        address creator,
        address agent,
        uint256 expectedVaultCount
    ) private view {
        MandateRegistry registry = MandateRegistry(state.registry);
        GrantlineTypes.Mandate memory mandate = registry.getMandate(mandateId);
        _require(mandate.createdBy == creator, "Mandate creator read mismatch");
        _require(mandate.agent == agent, "Mandate agent read mismatch");
        _require(registry.vaultMandateCount(state.vault) == expectedVaultCount, "Vault Mandate index count mismatch");
        _require(_containsMandate(registry, state.vault, mandateId), "Vault Mandate index missing record");
        _require(_containsCreatorMandate(registry, creator, mandateId), "creator Mandate index missing record");
        _require(_containsAgentMandate(registry, agent, mandateId), "agent Mandate index missing record");
    }

    function _assertEscalationIndexes(State memory state, bytes32 digest, address agent, uint256 expectedCount)
        private
        view
    {
        EscalationManager manager = EscalationManager(state.escalationManager);
        _require(manager.escalationCount() == expectedCount, "global Escalation index count mismatch");
        _require(manager.vaultEscalationCount(state.vault) == expectedCount, "Vault Escalation index count mismatch");
        _require(_containsEscalation(manager, digest), "global Escalation index missing record");
        _require(_containsVaultEscalation(manager, state.vault, digest), "Vault Escalation index missing record");
        _require(manager.agentEscalationCount(agent) >= 1, "agent Escalation index is empty");
        _require(_containsAgentEscalation(manager, agent, digest), "agent Escalation index missing record");
    }

    function _containsMandate(MandateRegistry registry, address vault, uint256 mandateId)
        private
        view
        returns (bool)
    {
        uint256 count = registry.vaultMandateCount(vault);
        for (uint256 index; index < count; index++) {
            if (registry.vaultMandateAt(vault, index) == mandateId) return true;
        }
        return false;
    }

    function _containsCreatorMandate(MandateRegistry registry, address creator, uint256 mandateId)
        private
        view
        returns (bool)
    {
        uint256 count = registry.creatorMandateCount(creator);
        for (uint256 index; index < count; index++) {
            if (registry.creatorMandateAt(creator, index) == mandateId) return true;
        }
        return false;
    }

    function _containsAgentMandate(MandateRegistry registry, address agent, uint256 mandateId)
        private
        view
        returns (bool)
    {
        uint256 count = registry.agentMandateCount(agent);
        for (uint256 index; index < count; index++) {
            if (registry.agentMandateAt(agent, index) == mandateId) return true;
        }
        return false;
    }

    function _containsEscalation(EscalationManager manager, bytes32 digest) private view returns (bool) {
        uint256 count = manager.escalationCount();
        for (uint256 index; index < count; index++) {
            if (manager.escalationAt(index) == digest) return true;
        }
        return false;
    }

    function _containsVaultEscalation(EscalationManager manager, address vault, bytes32 digest)
        private
        view
        returns (bool)
    {
        uint256 count = manager.vaultEscalationCount(vault);
        for (uint256 index; index < count; index++) {
            if (manager.vaultEscalationAt(vault, index) == digest) return true;
        }
        return false;
    }

    function _containsAgentEscalation(EscalationManager manager, address agent, bytes32 digest)
        private
        view
        returns (bool)
    {
        uint256 count = manager.agentEscalationCount(agent);
        for (uint256 index; index < count; index++) {
            if (manager.agentEscalationAt(agent, index) == digest) return true;
        }
        return false;
    }

    function _nativePlan(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) private pure returns (ActionTypes.ActionPlan memory) {
        return _assetPlan(mandateId, agent, nonce, amount, address(0), recipient, deadline);
    }

    function _assetPlan(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        uint256 amount,
        address asset,
        address recipient,
        uint256 deadline
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = _action(asset, recipient, amount);
        plan = ActionTypes.ActionPlan({
            mandateId: mandateId, agent: agent, nonce: nonce, deadline: deadline, actions: actions
        });
    }

    function _twoActionNativePlan(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        address firstRecipient,
        uint256 firstAmount,
        address secondRecipient,
        uint256 secondAmount
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _action(address(0), firstRecipient, firstAmount);
        actions[1] = _action(address(0), secondRecipient, secondAmount);
        plan = ActionTypes.ActionPlan({mandateId: mandateId, agent: agent, nonce: nonce, deadline: 0, actions: actions});
    }

    function _action(address asset, address recipient, uint256 amount)
        private
        pure
        returns (ActionTypes.Action memory action)
    {
        action = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: ActionTypes.TRANSFER_VERSION,
            parameters: abi.encode(ActionTypes.TransferParameters({asset: asset, recipient: recipient, amount: amount}))
        });
    }

    function _sign(State memory state, ActionTypes.ActionPlan memory plan, uint256 key)
        private
        returns (bytes memory signature)
    {
        (uint8 v, bytes32 r, bytes32 s) = integrationVm.sign(key, Grantline(state.hub).actionDigest(plan));
        signature = abi.encodePacked(r, s, v);
    }

    function _rules(uint256 maxNativeAmount, bool escalateNativeAmount, bool canDelegate)
        private
        pure
        returns (GrantlineTypes.MandateRules memory)
    {
        return GrantlineTypes.MandateRules({
            canDelegate: canDelegate,
            minNativeAmount: 0,
            maxNativeAmount: maxNativeAmount,
            escalateNativeAmount: escalateNativeAmount,
            minNativeUsd: 0,
            maxNativeUsd: 0,
            escalateNativeUsd: false
        });
    }

    function _preflight(uint256 minNativeBalance, bool escalateNativeBalance)
        private
        pure
        returns (GrantlineTypes.PreflightRules memory)
    {
        return GrantlineTypes.PreflightRules({
            minNativeBalance: minNativeBalance,
            escalateNativeBalance: escalateNativeBalance,
            minNativeUsdBalance: 0,
            escalateNativeUsdBalance: false
        });
    }

    function _requireAgentAddress(address actualAgent, address expectedAgent) private pure {
        if (actualAgent != expectedAgent) {
            revert AgentKeyMismatch(expectedAgent, actualAgent);
        }
    }

    function _require(bool condition, string memory check) private pure {
        if (!condition) revert IntegrationInvariant(check);
    }
}
