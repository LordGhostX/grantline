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

    struct RotationState {
        Vault vault;
        MandateRegistry registry;
        MandateEvaluator evaluator;
        EscalationManager manager;
        EscalationManager replacementManager;
        VaultExecutor replacementExecutor;
        ActionTypes.ActionPlan pendingPlan;
        ActionTypes.ActionPlan deniedPlan;
        bytes pendingSignature;
        bytes deniedSignature;
        bytes32 pendingDigest;
        bytes32 deniedDigest;
    }

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
        registry.updateMandate(
            plan.mandateId,
            _rules(1 ether, true, 0, false),
            MandateRegistry.PreflightRules({
                minNativeBalance: 1 ether,
                escalateNativeBalance: true
            })
        );
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
        assert(
            registry.reservedDigest(plan.mandateId, plan.agent, plan.nonce) ==
                bytes32(0)
        );
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

        registry.updateMandate(
            plan.mandateId,
            _rules(0, false, 0, false),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );
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

    function test_managerReplacementCannotBypassPendingOrDeniedReservations()
        public
    {
        RotationState memory state = _setupRotation();
        address recipient = address(0xBEEF);
        state.registry.updateMandate(
            state.pendingPlan.mandateId,
            _rules(0, false, 0, false),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );
        vm.deal(address(state.vault), 5 ether);

        bool pendingBypassReverted = _normalExecutionReverted(
            state.replacementExecutor,
            state.vault,
            state.pendingPlan,
            state.pendingSignature
        );
        bool deniedBypassReverted = _normalExecutionReverted(
            state.replacementExecutor,
            state.vault,
            state.deniedPlan,
            state.deniedSignature
        );

        assert(pendingBypassReverted);
        assert(deniedBypassReverted);
        assert(
            state.registry.reservedDigest(
                state.pendingPlan.mandateId,
                state.pendingPlan.agent,
                state.pendingPlan.nonce
            ) == state.pendingDigest
        );
        assert(
            state.registry.reservedDigest(
                state.deniedPlan.mandateId,
                state.deniedPlan.agent,
                state.deniedPlan.nonce
            ) == state.deniedDigest
        );
        assert(
            state.replacementManager.reservedDigest(
                state.pendingPlan.mandateId,
                state.pendingPlan.agent,
                state.pendingPlan.nonce
            ) == state.pendingDigest
        );
        assert(
            !state.registry.nonceUsed(
                state.pendingPlan.mandateId,
                state.pendingPlan.agent,
                state.pendingPlan.nonce
            )
        );
        assert(
            !state.registry.nonceUsed(
                state.deniedPlan.mandateId,
                state.deniedPlan.agent,
                state.deniedPlan.nonce
            )
        );
        assert(recipient.balance == 0);
        assert(address(state.vault).balance == 5 ether);
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
                escalateUsdAmount: false,
                canDelegate: false
            }),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
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
            _rules(1 ether, false, 0, false),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
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
            _rules(3 ether, false, 0, false),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
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

    function test_parentRevocationBlocksChildEscalationApprovalAndExecution()
        public
    {
        uint256 parentKey = 0xA11CE;
        uint256 childKey = 0xB0B;
        address parentAgent = vm.addr(parentKey);
        address childAgent = vm.addr(childKey);
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 parentId = registry.createMandate(
            address(vault),
            parentAgent,
            _delegatableEscalationRules(1 ether),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );

        vm.prank(parentAgent);
        uint256 childId = registry.createChildMandate(
            parentId,
            childAgent,
            _childEscalationRules(500_000_000_000_000),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );
        MandateEvaluator evaluator = new MandateEvaluator(
            address(registry),
            address(0),
            true
        );
        EscalationManager manager = new EscalationManager(address(evaluator));
        VaultExecutor executor = new VaultExecutor(
            address(evaluator),
            address(manager)
        );
        vault.setAuthority(address(executor));

        ActionTypes.ActionPlan memory plan = ActionTypes.ActionPlan({
            mandateId: childId,
            agent: childAgent,
            nonce: 1,
            deadline: 0,
            actions: new ActionTypes.Action[](1)
        });
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        bytes memory signature = _sign(evaluator, plan, childKey);
        bytes32 digest = manager.submit(plan, signature);

        registry.revokeMandate(parentId);

        bool approveReverted;
        try manager.approve(digest) {} catch {
            approveReverted = true;
        }
        bool executeReverted;
        try executor.executeEscalated(digest) {} catch {
            executeReverted = true;
        }
        manager.deny(digest);

        assert(approveReverted);
        assert(executeReverted);
        assert(manager.statusOf(digest) == EscalationManager.Status.DENIED);
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
            _rules(maxNativeAmount, escalateNativeAmount, 0, false),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
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
                escalateUsdAmount: escalateUsdAmount,
                canDelegate: false
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

    function _delegatableEscalationRules(
        uint256 maxNativeAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: true,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false,
                canDelegate: true
            });
    }

    function _childEscalationRules(
        uint256 maxNativeAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: true,
                minUsdAmount: 0,
                maxUsdAmount: 0,
                escalateUsdAmount: false,
                canDelegate: false
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

    function _copyPlanWithNonce(
        ActionTypes.ActionPlan memory source,
        uint256 nonce
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        plan = ActionTypes.ActionPlan({
            mandateId: source.mandateId,
            agent: source.agent,
            nonce: nonce,
            deadline: source.deadline,
            actions: new ActionTypes.Action[](source.actions.length)
        });
        for (uint256 index; index < source.actions.length; index++) {
            plan.actions[index] = source.actions[index];
        }
    }

    function _setupRotation() private returns (RotationState memory state) {
        uint256 privateKey;
        (
            state.vault,
            state.registry,
            state.evaluator,
            state.manager,
            ,
            state.pendingPlan,
            privateKey
        ) = _setup(1 ether, true);
        state.pendingPlan.actions[0] = _transferAction(
            address(0),
            address(0xBEEF),
            2 ether
        );
        state.pendingSignature = _sign(
            state.evaluator,
            state.pendingPlan,
            privateKey
        );
        state.pendingDigest = state.manager.submit(
            state.pendingPlan,
            state.pendingSignature
        );

        state.deniedPlan = _copyPlanWithNonce(state.pendingPlan, 2);
        state.deniedSignature = _sign(
            state.evaluator,
            state.deniedPlan,
            privateKey
        );
        state.deniedDigest = state.manager.submit(
            state.deniedPlan,
            state.deniedSignature
        );
        state.manager.deny(state.deniedDigest);

        state.replacementManager = new EscalationManager(
            address(state.evaluator)
        );
        state.replacementExecutor = new VaultExecutor(
            address(state.evaluator),
            address(state.replacementManager)
        );
        state.vault.setAuthority(address(state.replacementExecutor));

        ActionTypes.ActionPlan memory staleManagerPlan = _copyPlanWithNonce(
            state.pendingPlan,
            3
        );
        bool staleManagerReverted;
        try
            state.manager.submit(
                staleManagerPlan,
                _sign(state.evaluator, staleManagerPlan, privateKey)
            )
        {} catch {
            staleManagerReverted = true;
        }
        assert(staleManagerReverted);
        assert(
            state.registry.reservedDigest(
                staleManagerPlan.mandateId,
                staleManagerPlan.agent,
                staleManagerPlan.nonce
            ) == bytes32(0)
        );
    }

    function _normalExecutionReverted(
        VaultExecutor executor,
        Vault vault,
        ActionTypes.ActionPlan memory plan,
        bytes memory signature
    ) private returns (bool reverted) {
        try executor.execute(vault, plan, signature) {} catch {
            reverted = true;
        }
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
