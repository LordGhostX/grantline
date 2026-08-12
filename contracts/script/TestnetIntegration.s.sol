// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

interface TestnetIntegrationVm {
    function envAddress(string calldata name) external returns (address value);

    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract TestnetIntegration is ScriptBase {
    uint256 internal constant DEPOSIT_AMOUNT = 20_000_000_000_000_000;
    uint256 internal constant TRANSACTION_LIMIT = 1_000_000_000_000_000;
    uint256 internal constant SUCCESS_AMOUNT = 1_000_000_000_000_000;
    uint256 internal constant DENIED_AMOUNT = 1_100_000_000_000_000;
    uint256 internal constant REUSED_NONCE_AMOUNT = 500_000_000_000_000;
    uint256 internal constant ESCALATED_AMOUNT = 2_000_000_000_000_000;
    uint256 internal constant SECOND_ESCALATED_AMOUNT = 2_100_000_000_000_000;
    uint256 internal constant ROOT_PREFLIGHT_FLOOR = 15_500_000_000_000_000;
    uint256 internal constant CHILD_TRANSACTION_LIMIT = 1_500_000_000_000_000;
    uint256 internal constant CHILD_SUCCESS_AMOUNT = 500_000_000_000_000;
    uint256 internal constant GRANDCHILD_TRANSACTION_LIMIT =
        1_400_000_000_000_000;
    uint256 internal constant ROOT_LOOSENED_LIMIT = 3_000_000_000_000_000;
    uint256 internal constant ROOT_TIGHTENED_LIMIT = 1_200_000_000_000_000;
    uint256 internal constant SUCCESS_NONCE = 1;
    uint256 internal constant DENIED_NONCE = 2;
    uint256 internal constant FIRST_ESCALATION_NONCE = 3;
    uint256 internal constant CHILD_PREFLIGHT_NONCE = 2;

    TestnetIntegrationVm private constant integrationVm =
        TestnetIntegrationVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    error AgentKeyMismatch(address expectedAgent, address actualAgent);
    error UnexpectedVaultAuthority(
        address expectedAuthority,
        address actualAuthority
    );
    error UnexpectedVaultOwner(address expectedOwner, address actualOwner);
    error UnexpectedVaultBalance(uint256 actualBalance);

    struct Stack {
        Vault vault;
        MandateRegistry registry;
        MandateEvaluator evaluator;
        EscalationManager manager;
        VaultExecutor executor;
    }

    function fundAndCreate() external returns (uint256 mandateId) {
        Stack memory stack = _stack();
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.addr(ownerKey);
        address agent = _agentAddress();

        if (stack.vault.owner() != owner) {
            revert UnexpectedVaultOwner(owner, stack.vault.owner());
        }
        if (stack.vault.authority() != address(stack.executor)) {
            revert UnexpectedVaultAuthority(
                address(stack.executor),
                stack.vault.authority()
            );
        }
        if (address(stack.vault).balance != 0) {
            revert UnexpectedVaultBalance(address(stack.vault).balance);
        }

        mandateId = stack.registry.mandateCount() + 1;

        vm.startBroadcast(ownerKey);
        stack.vault.depositNative{value: DEPOSIT_AMOUNT}();
        stack.registry.createMandate(
            address(stack.vault),
            agent,
            _rules(TRANSACTION_LIMIT, true, true),
            _preflight(ROOT_PREFLIGHT_FLOOR, true)
        );
        vm.stopBroadcast();
    }

    function success(
        uint256 mandateId
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            SUCCESS_NONCE,
            SUCCESS_AMOUNT,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);

        vm.startBroadcast(agentKey);
        actionDigest = stack.executor.execute(stack.vault, plan, signature);
        vm.stopBroadcast();
    }

    function reuseDeniedNonce(
        uint256 mandateId
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            DENIED_NONCE,
            REUSED_NONCE_AMOUNT,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);

        vm.startBroadcast(agentKey);
        actionDigest = stack.executor.execute(stack.vault, plan, signature);
        vm.stopBroadcast();
    }

    function deniedCalldata(
        uint256 mandateId
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            DENIED_NONCE,
            DENIED_AMOUNT,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);
        callData = _callData(stack.vault, plan, signature);
    }

    function replayCalldata(
        uint256 mandateId
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            SUCCESS_NONCE,
            SUCCESS_AMOUNT,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);
        callData = _callData(stack.vault, plan, signature);
    }

    function reservedNormalCalldata(
        uint256 mandateId
    ) external returns (bytes memory callData) {
        callData = normalCalldata(
            mandateId,
            FIRST_ESCALATION_NONCE,
            ESCALATED_AMOUNT
        );
    }

    function normalCalldata(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) public returns (bytes memory callData) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            nonce,
            amount,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);
        callData = _callData(stack.vault, plan, signature);
    }

    function updateRootMandate(
        uint256 mandateId,
        uint256 maxNativeAmount,
        bool escalateNativeAmount
    ) external {
        _updateMandate(
            mandateId,
            _rules(maxNativeAmount, escalateNativeAmount, true),
            _preflight(ROOT_PREFLIGHT_FLOOR, true)
        );
    }

    function loosenRoot(uint256 mandateId) external {
        _updateMandate(
            mandateId,
            _rules(ROOT_LOOSENED_LIMIT, true, true),
            _preflight(ROOT_PREFLIGHT_FLOOR, true)
        );
    }

    function submitEscalation(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        (
            ActionTypes.ActionPlan memory plan,
            bytes memory signature
        ) = _signedPlan(stack.evaluator, mandateId, nonce, amount);

        vm.startBroadcast(agentKey);
        actionDigest = stack.manager.submit(plan, signature);
        vm.stopBroadcast();
    }

    function duplicateEscalationCalldata(
        uint256 mandateId
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        (
            ActionTypes.ActionPlan memory plan,
            bytes memory signature
        ) = _signedPlan(
                stack.evaluator,
                mandateId,
                FIRST_ESCALATION_NONCE,
                ESCALATED_AMOUNT
            );
        callData = abi.encodeWithSelector(
            EscalationManager.submit.selector,
            plan,
            signature
        );
    }

    function reservedEscalationCalldata(
        uint256 mandateId
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        (
            ActionTypes.ActionPlan memory plan,
            bytes memory signature
        ) = _signedPlan(
                stack.evaluator,
                mandateId,
                FIRST_ESCALATION_NONCE,
                SECOND_ESCALATED_AMOUNT
            );
        callData = abi.encodeWithSelector(
            EscalationManager.submit.selector,
            plan,
            signature
        );
    }

    function approveEscalation(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) external {
        Stack memory stack = _stack();
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        bytes32 actionDigest = _digest(
            stack.evaluator,
            mandateId,
            nonce,
            amount
        );

        vm.startBroadcast(ownerKey);
        stack.manager.approve(actionDigest);
        vm.stopBroadcast();
    }

    function approveEscalationCalldata(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        bytes32 actionDigest = _digest(
            stack.evaluator,
            mandateId,
            nonce,
            amount
        );
        callData = abi.encodeWithSelector(
            EscalationManager.approve.selector,
            actionDigest
        );
    }

    function executeEscalated(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        actionDigest = _digest(stack.evaluator, mandateId, nonce, amount);

        vm.startBroadcast(agentKey);
        stack.executor.executeEscalated(actionDigest);
        vm.stopBroadcast();
    }

    function createChildMandate(
        uint256 parentMandateId
    ) external returns (uint256 mandateId) {
        Stack memory stack = _stack();
        uint256 agentKey = _primaryKey();
        address delegatedAgent = _delegatedAgentAddress();

        vm.startBroadcast(agentKey);
        mandateId = stack.registry.createChildMandate(
            parentMandateId,
            delegatedAgent,
            _rules(CHILD_TRANSACTION_LIMIT, false, true),
            _preflight(ROOT_PREFLIGHT_FLOOR, false)
        );
        vm.stopBroadcast();
    }

    function childSuccess(
        uint256 childMandateId
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _delegatedKey();
        ActionTypes.ActionPlan memory plan = _delegatedPlan(
            childMandateId,
            SUCCESS_NONCE,
            CHILD_SUCCESS_AMOUNT,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);

        vm.startBroadcast(agentKey);
        actionDigest = stack.executor.execute(stack.vault, plan, signature);
        vm.stopBroadcast();
    }

    function childPreflightCalldata(
        uint256 childMandateId
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        uint256 agentKey = _delegatedKey();
        ActionTypes.ActionPlan memory plan = _delegatedPlan(
            childMandateId,
            CHILD_PREFLIGHT_NONCE,
            CHILD_TRANSACTION_LIMIT,
            _ownerAddress()
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);
        callData = _callData(stack.vault, plan, signature);
    }

    function updateChildPreflight(
        uint256 childMandateId,
        bool escalateNativeBalance
    ) external {
        _updateMandate(
            childMandateId,
            _rules(CHILD_TRANSACTION_LIMIT, false, true),
            _preflight(ROOT_PREFLIGHT_FLOOR, escalateNativeBalance)
        );
    }

    function submitDelegatedEscalation(
        uint256 childMandateId,
        uint256 nonce,
        uint256 amount
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _delegatedKey();
        (
            ActionTypes.ActionPlan memory plan,
            bytes memory signature
        ) = _signedDelegatedPlan(
                stack.evaluator,
                childMandateId,
                nonce,
                amount
            );

        vm.startBroadcast(agentKey);
        actionDigest = stack.manager.submit(plan, signature);
        vm.stopBroadcast();
    }

    function approveDelegatedEscalation(
        uint256 childMandateId,
        uint256 nonce,
        uint256 amount
    ) external {
        Stack memory stack = _stack();
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        bytes32 actionDigest = _delegatedDigest(
            stack.evaluator,
            childMandateId,
            nonce,
            amount
        );

        vm.startBroadcast(ownerKey);
        stack.manager.approve(actionDigest);
        vm.stopBroadcast();
    }

    function executeDelegatedEscalated(
        uint256 childMandateId,
        uint256 nonce,
        uint256 amount
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = _delegatedKey();
        actionDigest = _delegatedDigest(
            stack.evaluator,
            childMandateId,
            nonce,
            amount
        );

        vm.startBroadcast(agentKey);
        stack.executor.executeEscalated(actionDigest);
        vm.stopBroadcast();
    }

    function createGrandchildMandate(
        uint256 childMandateId
    ) external returns (uint256 mandateId) {
        Stack memory stack = _stack();
        uint256 agentKey = _delegatedKey();

        vm.startBroadcast(agentKey);
        mandateId = stack.registry.createChildMandate(
            childMandateId,
            _agentAddress(),
            _rules(GRANDCHILD_TRANSACTION_LIMIT, false, false),
            _preflight(ROOT_PREFLIGHT_FLOOR, false)
        );
        vm.stopBroadcast();
    }

    function tightenRoot(uint256 rootMandateId) external {
        _updateMandate(
            rootMandateId,
            _rules(ROOT_TIGHTENED_LIMIT, false, true),
            _preflight(ROOT_PREFLIGHT_FLOOR, true)
        );
    }

    function grandchildRevokeCalldata(
        uint256 grandchildMandateId
    ) external returns (bytes memory callData) {
        _delegatedKey();
        callData = abi.encodeWithSelector(
            MandateRegistry.revokeMandate.selector,
            grandchildMandateId
        );
    }

    function revokeMandate(uint256 mandateId) external {
        Stack memory stack = _stack();
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(ownerKey);
        stack.registry.revokeMandate(mandateId);
        vm.stopBroadcast();
    }

    function withdraw() external returns (uint256 amount) {
        Stack memory stack = _stack();
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable recipient = payable(vm.addr(ownerKey));
        amount = address(stack.vault).balance;

        vm.startBroadcast(ownerKey);
        stack.vault.withdrawNative(recipient, amount);
        vm.stopBroadcast();
    }

    function _stack() private returns (Stack memory stack) {
        string memory manifest = _manifest();
        stack.vault = Vault(
            payable(vm.parseJsonAddress(manifest, ".vault.address"))
        );
        stack.registry = MandateRegistry(
            vm.parseJsonAddress(manifest, ".mandateRegistry.address")
        );
        stack.evaluator = MandateEvaluator(
            vm.parseJsonAddress(manifest, ".mandateEvaluator.address")
        );
        stack.manager = EscalationManager(
            vm.parseJsonAddress(manifest, ".escalationManager.address")
        );
        stack.executor = VaultExecutor(
            vm.parseJsonAddress(manifest, ".vaultExecutor.address")
        );
    }

    function _updateMandate(
        uint256 mandateId,
        MandateRegistry.MandateRules memory rules,
        MandateRegistry.PreflightRules memory preflightRules
    ) private {
        Stack memory stack = _stack();
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(ownerKey);
        stack.registry.updateMandate(mandateId, rules, preflightRules);
        vm.stopBroadcast();
    }

    function _primaryKey() private returns (uint256 key) {
        key = vm.envUint("AGENT_PRIVATE_KEY");
        _requireAgentAddress(key, "AGENT_PUBLIC_KEY");
    }

    function _delegatedKey() private returns (uint256 key) {
        key = vm.envUint("DELEGATED_AGENT_PRIVATE_KEY");
        _requireAgentAddress(key, "DELEGATED_AGENT_PUBLIC_KEY");
    }

    function _requireAgentAddress(
        uint256 agentKey,
        string memory publicKeyName
    ) private {
        address actualAgent = vm.addr(agentKey);
        address expectedAgent = integrationVm.envAddress(publicKeyName);
        if (actualAgent != expectedAgent) {
            revert AgentKeyMismatch(expectedAgent, actualAgent);
        }
    }

    function _ownerAddress() private returns (address) {
        return vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    }

    function _agentAddress() private returns (address agent) {
        uint256 agentKey = _primaryKey();
        agent = vm.addr(agentKey);
    }

    function _delegatedAgentAddress() private returns (address agent) {
        uint256 agentKey = _delegatedKey();
        agent = vm.addr(agentKey);
    }

    function _plan(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount,
        address recipient
    ) private returns (ActionTypes.ActionPlan memory plan) {
        plan = _planForAgent(
            mandateId,
            nonce,
            amount,
            recipient,
            _agentAddress()
        );
    }

    function _delegatedPlan(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount,
        address recipient
    ) private returns (ActionTypes.ActionPlan memory plan) {
        plan = _planForAgent(
            mandateId,
            nonce,
            amount,
            recipient,
            _delegatedAgentAddress()
        );
    }

    function _planForAgent(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount,
        address recipient,
        address agent
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        ActionTypes.TransferParameters memory transfer = ActionTypes
            .TransferParameters({
                asset: address(0),
                recipient: recipient,
                amount: amount
            });
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: ActionTypes.TRANSFER_VERSION,
            parameters: abi.encode(transfer)
        });
        plan = ActionTypes.ActionPlan({
            mandateId: mandateId,
            agent: agent,
            nonce: nonce,
            deadline: 0,
            actions: actions
        });
    }

    function _sign(
        ActionTypes.ActionPlan memory plan,
        MandateEvaluator evaluator,
        uint256 agentKey
    ) private returns (bytes memory signature) {
        bytes32 digest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = integrationVm.sign(agentKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _callData(
        Vault vault,
        ActionTypes.ActionPlan memory plan,
        bytes memory signature
    ) private pure returns (bytes memory callData) {
        callData = abi.encodeWithSelector(
            VaultExecutor.execute.selector,
            vault,
            plan,
            signature
        );
    }

    function _signedPlan(
        MandateEvaluator evaluator,
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    )
        private
        returns (ActionTypes.ActionPlan memory plan, bytes memory signature)
    {
        uint256 agentKey = _primaryKey();
        plan = _plan(mandateId, nonce, amount, _ownerAddress());
        signature = _sign(plan, evaluator, agentKey);
    }

    function _signedDelegatedPlan(
        MandateEvaluator evaluator,
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    )
        private
        returns (ActionTypes.ActionPlan memory plan, bytes memory signature)
    {
        uint256 agentKey = _delegatedKey();
        plan = _delegatedPlan(mandateId, nonce, amount, _ownerAddress());
        signature = _sign(plan, evaluator, agentKey);
    }

    function _digest(
        MandateEvaluator evaluator,
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) private returns (bytes32 actionDigest) {
        actionDigest = _digestForAgent(
            evaluator,
            mandateId,
            nonce,
            amount,
            _agentAddress()
        );
    }

    function _delegatedDigest(
        MandateEvaluator evaluator,
        uint256 mandateId,
        uint256 nonce,
        uint256 amount
    ) private returns (bytes32 actionDigest) {
        actionDigest = _digestForAgent(
            evaluator,
            mandateId,
            nonce,
            amount,
            _delegatedAgentAddress()
        );
    }

    function _digestForAgent(
        MandateEvaluator evaluator,
        uint256 mandateId,
        uint256 nonce,
        uint256 amount,
        address agent
    ) private returns (bytes32 actionDigest) {
        ActionTypes.ActionPlan memory plan = _planForAgent(
            mandateId,
            nonce,
            amount,
            _ownerAddress(),
            agent
        );
        actionDigest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
    }

    function _rules(
        uint256 maxNativeAmount,
        bool escalateNativeAmount,
        bool canDelegate
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                canDelegate: canDelegate,
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: escalateNativeAmount,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false
            });
    }

    function _preflight(
        uint256 minNativeBalance,
        bool escalateNativeBalance
    ) private pure returns (MandateRegistry.PreflightRules memory) {
        return
            MandateRegistry.PreflightRules({
                minNativeBalance: minNativeBalance,
                escalateNativeBalance: escalateNativeBalance
            });
    }
}
