// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

interface GrantlineVm {
    function addr(uint256 privateKey) external returns (address);

    function deal(address account, uint256 amount) external;

    function prank(address sender) external;

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);

    function expectRevert() external;

    function expectRevert(bytes calldata revertData) external;
}

contract GrantlineTestToken {
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
        if (balanceOf[sender] < amount || allowance[sender][msg.sender] < amount) {
            return false;
        }
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract VaultV2 is Vault {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract MandateRegistryV2 is MandateRegistry {
    function marker() external pure returns (uint256) {
        return 2;
    }
}

contract GrantlineTest {
    GrantlineVm private constant vm = GrantlineVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 private constant AGENT_KEY = 0xA11CE;
    uint256 private constant OTHER_AGENT_KEY = 0xB0B;

    struct Fixture {
        Grantline hub;
        GrantlineAdmin admin;
        address vault;
        uint256 mandateId;
        address controller;
        address agent;
    }

    function test_createsAndFundsVaultThroughGrantline() public {
        Fixture memory fixture = _fixture();
        Grantline.VaultView memory vault = fixture.hub.getVault(fixture.vault);

        assert(vault.controller == fixture.controller);
        assert(vault.owner == address(fixture.hub));
        assert(vault.authority == fixture.hub.executor());
        assert(vault.nativeBalance == 5 ether);
        assert(fixture.hub.isRegisteredVault(fixture.vault));
    }

    function test_controllerCanPauseVaultAndRetainRecoveryOperations() public {
        Fixture memory fixture = _fixture();
        address otherController = address(0xCAFE);

        vm.prank(otherController);
        vm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, fixture.vault, otherController));
        fixture.hub.pauseVault(fixture.vault);

        fixture.hub.pauseVault(fixture.vault);
        assert(fixture.hub.getVault(fixture.vault).paused);

        ActionTypes.ActionPlan memory plan =
            _plan(fixture.mandateId, fixture.agent, 101, _transfer(address(0), address(0xBEEF), 1 ether));
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(AGENT_KEY, fixture.hub.actionDigest(plan)));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.VAULT_PAUSED));

        vm.expectRevert(abi.encodeWithSelector(Grantline.VaultIsPaused.selector, fixture.vault));
        fixture.hub
            .createMandate(fixture.vault, fixture.agent, _rules(1 ether, false), _preflight(0, false, 0, false), 0, 0);

        fixture.hub.withdrawNative(fixture.vault, payable(otherController), 1 ether);
        fixture.hub.depositNative{value: 1 ether}(fixture.vault);

        fixture.hub.unpauseVault(fixture.vault);
        assert(!fixture.hub.getVault(fixture.vault).paused);
        fixture.hub.execute(plan, _sign(AGENT_KEY, fixture.hub.actionDigest(plan)));
        assert(otherController.balance == 1 ether);
        assert(address(0xBEEF).balance == 1 ether);
    }

    function test_controllerIsolationAndDirectModuleRejection() public {
        Fixture memory fixture = _fixture();
        address otherController = address(0xCAFE);

        vm.prank(otherController);
        vm.expectRevert();
        fixture.hub.withdrawNative(fixture.vault, payable(otherController), 1 ether);

        address registry = fixture.hub.registry();
        vm.expectRevert();
        MandateRegistry(registry).revokeMandate(fixture.mandateId, otherController);

        vm.expectRevert();
        Vault(payable(fixture.vault)).withdrawNative(payable(otherController), 1 ether);
    }

    function test_internalModulesRejectDirectCalls() public {
        Fixture memory fixture = _fixture();
        address caller = address(0xCAFE);
        ActionTypes.ActionPlan memory plan =
            _plan(fixture.mandateId, fixture.agent, 9, _transfer(address(0), address(0xD00D), 1 ether));
        bytes32 digest = fixture.hub.actionDigest(plan);

        (bool evaluatorSuccess,) = address(MandateEvaluator(fixture.hub.evaluator()))
            .call(abi.encodeCall(MandateEvaluator.evaluate, (plan, bytes(""), digest, false)));
        assert(!evaluatorSuccess);

        (bool managerSuccess,) = address(EscalationManager(fixture.hub.escalationManager()))
            .call(abi.encodeCall(EscalationManager.submit, (plan, bytes(""), digest, caller)));
        assert(!managerSuccess);

        (bool executorSuccess,) = address(VaultExecutor(fixture.hub.executor()))
            .call(abi.encodeCall(VaultExecutor.execute, (plan, bytes(""), digest)));
        assert(!executorSuccess);

        (bool factorySuccess,) =
            address(VaultFactory(fixture.hub.vaultFactory())).call(abi.encodeCall(VaultFactory.createVault, (caller)));
        assert(!factorySuccess);
    }

    function test_permissionlessSignedExecutionUsesGrantlineDomain() public {
        Fixture memory fixture = _fixture();
        address recipient = address(0xD00D);
        ActionTypes.ActionPlan memory plan =
            _plan(fixture.mandateId, fixture.agent, 1, _transfer(address(0), recipient, 1 ether));
        bytes memory signature = _sign(AGENT_KEY, fixture.hub.actionDigest(plan));

        fixture.hub.execute(plan, signature);

        assert(recipient.balance == 1 ether);
        assert(MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 1));
    }

    function test_effectivePolicyReadsRejectInvalidAndRevokedMandates() public {
        Fixture memory fixture = _fixture();
        MandateRegistry registry = MandateRegistry(fixture.hub.registry());

        GrantlineTypes.MandateRules memory effectiveRules = fixture.hub.getEffectiveRules(fixture.mandateId);
        GrantlineTypes.PreflightRules memory effectivePreflightRules =
            fixture.hub.getEffectivePreflightRules(fixture.mandateId);
        assert(effectiveRules.maxNativeAmount == registry.getMandate(fixture.mandateId).rules.maxNativeAmount);
        assert(
            effectivePreflightRules.minNativeBalance
                == registry.getMandate(fixture.mandateId).preflightRules.minNativeBalance
        );

        uint256 unknownMandateId = registry.mandateCount() + 1;
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotFound.selector, uint256(0)));
        fixture.hub.getEffectiveRules(0);
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotFound.selector, uint256(0)));
        fixture.hub.getEffectivePreflightRules(0);
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotFound.selector, unknownMandateId));
        fixture.hub.getEffectiveRules(unknownMandateId);
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.MandateNotFound.selector, unknownMandateId));
        fixture.hub.getEffectivePreflightRules(unknownMandateId);

        fixture.hub.revokeMandate(fixture.mandateId);
        vm.expectRevert(
            abi.encodeWithSelector(
                MandateRegistry.MandateLineageInactive.selector, fixture.mandateId, fixture.mandateId
            )
        );
        fixture.hub.getEffectiveRules(fixture.mandateId);
        vm.expectRevert(
            abi.encodeWithSelector(
                MandateRegistry.MandateLineageInactive.selector, fixture.mandateId, fixture.mandateId
            )
        );
        fixture.hub.getEffectivePreflightRules(fixture.mandateId);
    }

    function test_tokenDepositUsesVaultSpecificApproval() public {
        Fixture memory fixture = _fixture();
        GrantlineTestToken token = new GrantlineTestToken();
        token.mint(fixture.controller, 10 ether);

        vm.prank(fixture.controller);
        token.approve(fixture.vault, 3 ether);
        vm.prank(fixture.controller);
        fixture.hub.depositToken(fixture.vault, address(token), 3 ether);

        assert(token.balanceOf(fixture.vault) == 3 ether);
        assert(Vault(payable(fixture.vault)).tokenBalance(address(token)) == 3 ether);
    }

    function test_childMandateAndControllerReassignment() public {
        Fixture memory fixture = _fixture();
        address childAgent = vm.addr(OTHER_AGENT_KEY);
        GrantlineTypes.MandateRules memory childRules = _rules(2 ether, false);

        vm.prank(fixture.agent);
        uint256 childId = fixture.hub
            .createChildMandate(fixture.mandateId, childAgent, childRules, _preflight(0, false, 0, false), 0, 0);
        assert(fixture.hub.getMandate(childId).agent == childAgent);

        address newController = address(0xF00D);
        fixture.admin.setVaultController(fixture.vault, newController);

        vm.prank(fixture.controller);
        vm.expectRevert();
        fixture.hub.updateMandate(fixture.mandateId, childRules, _preflight(0, false, 0, false), 0, 0);

        vm.prank(newController);
        fixture.hub.updateMandate(fixture.mandateId, childRules, _preflight(0, false, 0, false), 0, 0);
        assert(fixture.hub.getMandate(fixture.mandateId).controller == newController);
    }

    function test_escalationSubmissionApprovalAndExecutionThroughHub() public {
        Fixture memory fixture = _fixtureWithRules(_rules(1 ether, true));
        address recipient = address(0xBEEF);
        ActionTypes.ActionPlan memory plan =
            _plan(fixture.mandateId, fixture.agent, 8, _transfer(address(0), recipient, 2 ether));
        bytes memory signature = _sign(AGENT_KEY, fixture.hub.actionDigest(plan));

        bytes32 digest = fixture.hub.submitEscalation(plan, signature);
        assert(fixture.hub.escalationStatus(digest) == 1);

        vm.prank(fixture.controller);
        fixture.hub.approveEscalation(digest);
        assert(fixture.hub.escalationStatus(digest) == 2);

        fixture.hub.executeEscalated(digest);
        assert(recipient.balance == 2 ether);
        assert(fixture.hub.escalationStatus(digest) == 4);
    }

    function test_protocolAdminCanChangeTemplateAndUpgradeOneVault() public {
        Fixture memory fixture = _fixture();
        address secondVault = fixture.hub.createVault();
        VaultV2 implementation = new VaultV2();

        fixture.admin.setVaultImplementation(address(implementation), 1);
        address thirdVault = fixture.hub.createVault();
        assert(fixture.hub.getVault(secondVault).implementation != address(implementation));
        assert(fixture.hub.getVault(fixture.vault).implementation != address(implementation));

        fixture.admin.upgradeVault(fixture.vault, address(implementation), 1, "");
        assert(VaultV2(payable(fixture.vault)).marker() == 2);
        assert(fixture.hub.getVault(fixture.vault).implementation == address(implementation));
        assert(Vault(payable(fixture.vault)).grantline() == address(fixture.hub));
        assert(fixture.hub.getVault(secondVault).implementation != address(implementation));
        assert(fixture.hub.getVault(thirdVault).implementation == address(implementation));
    }

    function test_vaultUpgradeMetadataMismatchRollsBack() public {
        Fixture memory fixture = _fixture();
        address previousImplementation = fixture.hub.getVault(fixture.vault).implementation;
        VaultV2 implementation = new VaultV2();

        (bool success,) = address(fixture.admin)
            .call(abi.encodeCall(GrantlineAdmin.upgradeVault, (fixture.vault, address(implementation), 2, bytes(""))));
        assert(!success);
        assert(fixture.hub.getVault(fixture.vault).implementation == previousImplementation);
    }

    function test_moduleUpgradePreservesRegistryState() public {
        Fixture memory fixture = _fixture();
        MandateRegistryV2 implementation = new MandateRegistryV2();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: fixture.hub.REGISTRY_MODULE(), implementation: address(implementation), version: 1, data: ""
        });

        fixture.admin.upgradeModules(upgrades);

        assert(MandateRegistryV2(fixture.hub.registry()).marker() == 2);
        assert(MandateRegistry(fixture.hub.registry()).mandateCount() == 1);
        assert(MandateRegistry(fixture.hub.registry()).isRegisteredVault(fixture.vault));
    }

    function _fixture() private returns (Fixture memory fixture) {
        return _fixtureWithRules(_rules(2 ether, false));
    }

    function _fixtureWithRules(GrantlineTypes.MandateRules memory rules) private returns (Fixture memory fixture) {
        fixture.controller = address(this);
        fixture.agent = vm.addr(AGENT_KEY);
        (fixture.hub, fixture.admin) = _deployHub();

        vm.deal(fixture.controller, 10 ether);
        fixture.vault = _createVault(fixture.hub, fixture.controller);
        vm.prank(fixture.controller);
        fixture.hub.depositNative{value: 5 ether}(fixture.vault);

        vm.prank(fixture.controller);
        fixture.mandateId =
            fixture.hub.createMandate(fixture.vault, fixture.agent, rules, _preflight(0, false, 0, false), 0, 0);
    }

    function _deployHub() private returns (Grantline hub, GrantlineAdmin admin) {
        Grantline grantlineImplementation = new Grantline();
        MandateRegistry registryImplementation = new MandateRegistry();
        MandateEvaluator evaluatorImplementation = new MandateEvaluator();
        EscalationManager managerImplementation = new EscalationManager();
        VaultExecutor executorImplementation = new VaultExecutor();
        Vault vaultImplementation = new Vault();

        hub = Grantline(
            address(
                new ERC1967Proxy(
                    address(grantlineImplementation), abi.encodeCall(Grantline.initialize, (address(this)))
                )
            )
        );
        admin = new GrantlineAdmin(address(hub));
        hub.setAdminController(address(admin));
        address registry = address(
            new ERC1967Proxy(
                address(registryImplementation), abi.encodeCall(MandateRegistry.initialize, (address(hub)))
            )
        );
        address evaluator = address(
            new ERC1967Proxy(
                address(evaluatorImplementation),
                abi.encodeCall(MandateEvaluator.initialize, (address(hub), registry, address(0), 0, address(0)))
            )
        );
        address manager = address(
            new ERC1967Proxy(
                address(managerImplementation),
                abi.encodeCall(EscalationManager.initialize, (address(hub), evaluator, registry))
            )
        );
        address executor = address(
            new ERC1967Proxy(
                address(executorImplementation),
                abi.encodeCall(VaultExecutor.initialize, (address(hub), evaluator, registry, manager))
            )
        );
        address factory = address(
            new ERC1967Proxy(
                address(new VaultFactory()),
                abi.encodeCall(VaultFactory.initialize, (address(hub), address(vaultImplementation), 1, executor))
            )
        );
        admin.configureModules(registry, evaluator, manager, executor, factory, new ActionTypes.SwapAdapterConfig[](0));
    }

    function _createVault(Grantline hub, address controller) private returns (address vault) {
        vm.prank(controller);
        vault = hub.createVault();
    }

    function _rules(uint256 maxNativeAmount, bool escalate) private pure returns (GrantlineTypes.MandateRules memory) {
        return GrantlineTypes.MandateRules({
            canDelegate: true,
            minNativeAmount: 0,
            maxNativeAmount: maxNativeAmount,
            escalateNativeAmount: escalate,
            minNativeUsd: 0,
            maxNativeUsd: 0,
            escalateNativeUsd: false
        });
    }

    function _preflight(
        uint256 minNativeBalance,
        bool escalate,
        uint256 minNativeUsdBalance,
        bool escalateNativeUsdBalance
    ) private pure returns (GrantlineTypes.PreflightRules memory) {
        return GrantlineTypes.PreflightRules({
            minNativeBalance: minNativeBalance,
            escalateNativeBalance: escalate,
            minNativeUsdBalance: minNativeUsdBalance,
            escalateNativeUsdBalance: escalateNativeUsdBalance
        });
    }

    function _transfer(address asset, address recipient, uint256 amount)
        private
        pure
        returns (ActionTypes.Action memory)
    {
        return ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: 1,
            parameters: abi.encode(ActionTypes.TransferParameters({asset: asset, recipient: recipient, amount: amount}))
        });
    }

    function _plan(uint256 mandateId, address agent, uint256 nonce, ActionTypes.Action memory action)
        private
        pure
        returns (ActionTypes.ActionPlan memory plan)
    {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = action;
        plan = ActionTypes.ActionPlan({mandateId: mandateId, agent: agent, nonce: nonce, deadline: 0, actions: actions});
    }

    function _sign(uint256 privateKey, bytes32 digest) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
