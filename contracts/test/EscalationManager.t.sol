// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";

interface EscalationVm {
    function addr(uint256 privateKey) external returns (address);

    function deal(address account, uint256 newBalance) external;

    function prank(address sender) external;

    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract EscalationManagerTest {
    EscalationVm private constant vm =
        EscalationVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_ownerApprovesStoredPlanAndExecutorReevaluatesAndExecutes()
        public
    {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, true);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);

        EscalationManager.Escalation memory stored = manager.getEscalation(
            digest
        );
        assert(stored.status == EscalationManager.Status.PENDING);
        assert(stored.plan.mandateId == plan.mandateId);
        assert(stored.plan.agent == plan.agent);
        assert(stored.plan.nonce == plan.nonce);
        assert(stored.plan.actions.length == 1);
        assert(
            keccak256(stored.plan.actions[0].parameters) ==
                keccak256(plan.actions[0].parameters)
        );
        assert(keccak256(stored.signature) == keccak256(signature));
        assert(
            manager.reservedDigest(plan.mandateId, plan.agent, plan.nonce) ==
                digest
        );

        manager.approve(digest);
        assert(manager.statusOf(digest) == EscalationManager.Status.APPROVED);

        vm.deal(address(vault), 3 ether);
        vm.prank(address(0xCAFE));
        assert(executor.executeEscalated(digest) == digest);

        assert(recipient.balance == 2 ether);
        assert(address(vault).balance == 1 ether);
        assert(registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(manager.statusOf(digest) == EscalationManager.Status.EXECUTED);
    }

    function test_deniedEscalationReservesNonceAndBlocksNormalBypass() public {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, true);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);
        manager.deny(digest);

        registry.updateMandate(plan.mandateId, _rules(0, false, 0, false));
        vm.deal(address(vault), 3 ether);

        bool reverted;
        try executor.execute(vault, plan, signature) {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(!registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(recipient.balance == 0);
        assert(address(vault).balance == 3 ether);
        assert(manager.statusOf(digest) == EscalationManager.Status.DENIED);
    }

    function test_ownerApprovesEscalatedMinimumAndExecutorExecutes() public {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0, true);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 1 ether);
        registry.updateMandate(
            plan.mandateId,
            MandateRegistry.MandateRules({
                minNativeAmount: 2 ether,
                maxNativeAmount: 0,
                escalateNativeAmount: true,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false
            })
        );
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);
        manager.approve(digest);

        vm.deal(address(vault), 2 ether);
        assert(executor.executeEscalated(digest) == digest);
        assert(recipient.balance == 1 ether);
        assert(address(vault).balance == 1 ether);
        assert(manager.statusOf(digest) == EscalationManager.Status.EXECUTED);
    }

    function test_executionReevaluatesUpdatedMandateAfterApproval() public {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, true);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);
        manager.approve(digest);

        registry.updateMandate(
            plan.mandateId,
            _rules(1 ether, false, 0, false)
        );
        vm.deal(address(vault), 3 ether);

        bool reverted;
        try executor.executeEscalated(digest) {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(!registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(recipient.balance == 0);
        assert(address(vault).balance == 3 ether);
        assert(manager.statusOf(digest) == EscalationManager.Status.APPROVED);
    }

    function test_executionReevaluatesLoosenedMandateAfterApproval() public {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, true);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);
        manager.approve(digest);

        registry.updateMandate(
            plan.mandateId,
            _rules(3 ether, false, 0, false)
        );
        vm.deal(address(vault), 3 ether);

        assert(executor.executeEscalated(digest) == digest);
        assert(recipient.balance == 2 ether);
        assert(address(vault).balance == 1 ether);
        assert(registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(manager.statusOf(digest) == EscalationManager.Status.EXECUTED);
    }

    function test_revocationBlocksNormalAndApprovedExecution() public {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, true);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);
        manager.approve(digest);
        registry.revokeMandate(plan.mandateId);
        vm.deal(address(vault), 3 ether);

        bool escalatedReverted;
        try executor.executeEscalated(digest) {} catch {
            escalatedReverted = true;
        }

        ActionTypes.ActionPlan memory normalPlan = plan;
        normalPlan.nonce = 2;
        normalPlan.actions[0] = _transferAction(address(0), recipient, 1 ether);
        bool normalReverted;
        try
            executor.execute(
                vault,
                normalPlan,
                _sign(evaluator, normalPlan, privateKey)
            )
        {} catch {
            normalReverted = true;
        }

        assert(escalatedReverted);
        assert(normalReverted);
        assert(!registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(
            !registry.nonceUsed(
                normalPlan.mandateId,
                normalPlan.agent,
                normalPlan.nonce
            )
        );
        assert(recipient.balance == 0);
        assert(address(vault).balance == 3 ether);
        assert(manager.statusOf(digest) == EscalationManager.Status.APPROVED);
    }

    function test_revokedPendingEscalationCannotApproveButCanBeDenied() public {
        (
            ,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            ,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, true);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);
        bytes32 digest = manager.submit(plan, signature);
        registry.revokeMandate(plan.mandateId);

        bool approveReverted;
        try manager.approve(digest) {} catch {
            approveReverted = true;
        }
        manager.deny(digest);

        assert(approveReverted);
        assert(manager.statusOf(digest) == EscalationManager.Status.DENIED);
        assert(
            manager.reservedDigest(plan.mandateId, plan.agent, plan.nonce) ==
                digest
        );
    }

    function test_unconfiguredLimitOverrunCannotBeSubmittedForEscalation()
        public
    {
        (
            ,
            ,
            MandateEvaluator evaluator,
            EscalationManager manager,
            ,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether, false);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 2 ether);
        bytes memory signature = _sign(evaluator, plan, privateKey);

        bool reverted;
        try manager.submit(plan, signature) {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function _setup(
        uint256 maxNativeAmount,
        bool escalateNativeAmount
    )
        private
        returns (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            EscalationManager manager,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        vault = new Vault();
        registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(maxNativeAmount, escalateNativeAmount, 0, false)
        );
        evaluator = new MandateEvaluator(address(registry), address(0), true);
        manager = new EscalationManager(address(evaluator));
        executor = new VaultExecutor(address(evaluator), address(manager));
        vault.setAuthority(address(executor));
        plan = ActionTypes.ActionPlan({
            mandateId: mandateId,
            agent: agent,
            nonce: 1,
            deadline: 0,
            actions: new ActionTypes.Action[](1)
        });
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
    }

    function _rules(
        uint256 maxNativeAmount,
        bool escalateNativeAmount,
        uint256 maxUsdAmount,
        bool escalateUsdAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: escalateNativeAmount,
                minUsdAmount: 0,
                maxUsdAmount: maxUsdAmount,
                escalateUsdAmount: escalateUsdAmount
            });
    }

    function _transferAction(
        address asset,
        address recipient,
        uint256 amount
    ) private pure returns (ActionTypes.Action memory) {
        return
            ActionTypes.Action({
                actionType: ActionTypes.ActionType.TRANSFER,
                version: 1,
                parameters: abi.encode(
                    ActionTypes.TransferParameters({
                        asset: asset,
                        recipient: recipient,
                        amount: amount
                    })
                )
            });
    }

    function _sign(
        MandateEvaluator evaluator,
        ActionTypes.ActionPlan memory plan,
        uint256 privateKey
    ) private returns (bytes memory signature) {
        bytes32 digest = ActionSignature.digest(
            plan,
            address(evaluator),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
