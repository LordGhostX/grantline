// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
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
    uint256 internal constant DEPOSIT_AMOUNT = 3_000_000_000_000_000;
    uint256 internal constant TRANSACTION_LIMIT = 1_000_000_000_000_000;
    uint256 internal constant SUCCESS_AMOUNT = 1_000_000_000_000_000;
    uint256 internal constant DENIED_AMOUNT = 1_100_000_000_000_000;
    uint256 internal constant SUCCESS_NONCE = 1;
    uint256 internal constant DENIED_NONCE = 2;

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
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: TRANSACTION_LIMIT,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false
            })
        );
        vm.stopBroadcast();
    }

    function success(
        uint256 mandateId
    ) external returns (bytes32 actionDigest) {
        Stack memory stack = _stack();
        uint256 agentKey = vm.envUint("BURNER_AGENT_PRIVATE_KEY");
        address recipient = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            SUCCESS_NONCE,
            SUCCESS_AMOUNT,
            recipient
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
        uint256 agentKey = vm.envUint("BURNER_AGENT_PRIVATE_KEY");
        address recipient = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            DENIED_NONCE,
            DENIED_AMOUNT,
            recipient
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);
        callData = _callData(stack.vault, plan, signature);
    }

    function replayCalldata(
        uint256 mandateId
    ) external returns (bytes memory callData) {
        Stack memory stack = _stack();
        uint256 agentKey = vm.envUint("BURNER_AGENT_PRIVATE_KEY");
        address recipient = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        ActionTypes.ActionPlan memory plan = _plan(
            mandateId,
            SUCCESS_NONCE,
            SUCCESS_AMOUNT,
            recipient
        );
        bytes memory signature = _sign(plan, stack.evaluator, agentKey);
        callData = _callData(stack.vault, plan, signature);
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
        stack.executor = VaultExecutor(
            vm.parseJsonAddress(manifest, ".vaultExecutor.address")
        );
    }

    function _agentAddress() private returns (address agent) {
        uint256 agentKey = vm.envUint("BURNER_AGENT_PRIVATE_KEY");
        agent = vm.addr(agentKey);
        address expectedAgent = integrationVm.envAddress(
            "BURNER_AGENT_PUBLIC_KEY"
        );
        if (agent != expectedAgent) {
            revert AgentKeyMismatch(expectedAgent, agent);
        }
    }

    function _plan(
        uint256 mandateId,
        uint256 nonce,
        uint256 amount,
        address recipient
    ) private returns (ActionTypes.ActionPlan memory plan) {
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
            agent: _agentAddress(),
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
}
