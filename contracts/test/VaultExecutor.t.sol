// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {IUsdValueProvider, MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";

interface ExecutorVm {
    function addr(uint256 privateKey) external returns (address);

    function deal(address account, uint256 newBalance) external;

    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData
    ) external;

    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract ExecutorMockERC20 {
    mapping(address account => uint256) public balanceOf;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract FalseReturnToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract NoReturnToken {
    fallback() external {}
}

contract MalformedReturnToken {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(31, 1)
        }
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert();
    }
}

contract ReentrantNativeRecipient {
    address public executor;
    bytes public nestedCallData;
    bool public attempted;
    bool public blocked;

    function configure(
        address executor_,
        bytes calldata nestedCallData_
    ) external {
        executor = executor_;
        nestedCallData = nestedCallData_;
    }

    receive() external payable {
        attempted = true;
        (bool success, ) = executor.call(nestedCallData);
        blocked = !success;
    }
}

contract ExecutorMockUsdValueProvider is IUsdValueProvider {
    uint256 private immutable _usdAmount;
    bool private immutable _available;

    constructor(uint256 usdAmount, bool available) {
        _usdAmount = usdAmount;
        _available = available;
    }

    function quoteUsd(
        address,
        uint256
    ) external view returns (uint256 usdAmount, bool available) {
        return (_usdAmount, _available);
    }
}

contract VaultExecutorTest {
    event ActionPlanExecuted(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed agent,
        address vault,
        uint256 nonce,
        uint256 nativeAmount,
        uint256 usdAmount,
        bool usdLimitSkipped,
        uint256 actionCount,
        uint256 nativeBalanceAfter
    );

    ExecutorVm private constant vm =
        ExecutorVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_executesSignedNativePlanThroughVault() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address recipient = address(0xBEEF);
        plan.actions[0] = _transferAction(address(0), recipient, 1 ether);
        vm.deal(address(vault), 2 ether);

        bytes32 expectedDigest = ActionSignature.digest(
            plan,
            address(executor.evaluator()),
            block.chainid
        );
        vm.expectEmit(true, true, true, true);
        emit ActionPlanExecuted(
            expectedDigest,
            plan.mandateId,
            plan.agent,
            address(vault),
            plan.nonce,
            1 ether,
            0,
            false,
            1,
            1 ether
        );
        bytes32 actionDigest = executor.execute(
            vault,
            plan,
            _sign(executor, plan, privateKey)
        );

        assert(
            actionDigest ==
                ActionSignature.digest(
                    plan,
                    address(executor.evaluator()),
                    block.chainid
                )
        );
        assert(recipient.balance == 1 ether);
        assert(address(vault).balance == 1 ether);
    }

    function test_rejectsUnsupportedActionVersionBeforeExecution() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address recipient = address(0xBEEF);
        vm.deal(address(vault), 2 ether);
        plan.actions[0].version = 2;

        bool reverted;
        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(!executor.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(recipient.balance == 0);
        assert(address(vault).balance == 2 ether);
    }

    function test_executesSignedTokenPlanThroughVault() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        ExecutorMockERC20 token = new ExecutorMockERC20();
        address recipient = address(0xBEEF);
        token.mint(address(vault), 100 ether);
        plan.actions[0] = _transferAction(address(token), recipient, 40 ether);

        bytes32 expectedDigest = ActionSignature.digest(
            plan,
            address(executor.evaluator()),
            block.chainid
        );
        vm.expectEmit(true, true, true, true);
        emit ActionPlanExecuted(
            expectedDigest,
            plan.mandateId,
            plan.agent,
            address(vault),
            plan.nonce,
            0,
            0,
            false,
            1,
            0
        );
        executor.execute(vault, plan, _sign(executor, plan, privateKey));

        assert(token.balanceOf(address(vault)) == 60 ether);
        assert(token.balanceOf(recipient) == 40 ether);
    }

    function test_recordsUsdValuationInExecutionEvent() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setupWithUsd(2 ether, 500e18, 500e18);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        vm.deal(address(vault), 2 ether);

        bytes32 expectedDigest = ActionSignature.digest(
            plan,
            address(executor.evaluator()),
            block.chainid
        );
        vm.expectEmit(true, true, true, true);
        emit ActionPlanExecuted(
            expectedDigest,
            plan.mandateId,
            plan.agent,
            address(vault),
            plan.nonce,
            1 ether,
            500e18,
            false,
            1,
            1 ether
        );

        executor.execute(vault, plan, _sign(executor, plan, privateKey));
    }

    function test_rejectsReplayedPlan() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address recipient = address(0xBEEF);
        vm.deal(address(vault), 2 ether);
        bytes memory signature = _sign(executor, plan, privateKey);

        executor.execute(vault, plan, signature);

        bool reverted;
        try executor.execute(vault, plan, signature) {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(executor.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(recipient.balance == 1 ether);
        assert(address(vault).balance == 1 ether);
    }

    function test_rejectsReplayAfterExecutorReplacement() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address recipient = address(0xBEEF);
        vm.deal(address(vault), 2 ether);
        bytes memory signature = _sign(executor, plan, privateKey);

        executor.execute(vault, plan, signature);

        VaultExecutor replacement = new VaultExecutor(
            address(executor.evaluator()),
            address(executor.escalationManager())
        );
        vault.setAuthority(address(replacement));

        bool reverted;
        try replacement.execute(vault, plan, signature) {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(replacement.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(recipient.balance == 1 ether);
        assert(address(vault).balance == 1 ether);
    }

    function test_rejectsDifferentPlanWithUsedNonce() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address firstRecipient = address(0xBEEF);
        address secondRecipient = address(0xCAFE);
        vm.deal(address(vault), 2 ether);

        executor.execute(vault, plan, _sign(executor, plan, privateKey));

        ActionTypes.ActionPlan memory secondPlan = plan;
        secondPlan.actions = new ActionTypes.Action[](1);
        secondPlan.actions[0] = _transferAction(
            address(0),
            secondRecipient,
            1 ether
        );
        bool reverted;

        try
            executor.execute(
                vault,
                secondPlan,
                _sign(executor, secondPlan, privateKey)
            )
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(firstRecipient.balance == 1 ether);
        assert(secondRecipient.balance == 0);
        assert(address(vault).balance == 1 ether);
    }

    function test_allowsDifferentNoncesWithoutStrictOrdering() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address firstRecipient = address(0xBEEF);
        address secondRecipient = address(0xCAFE);
        vm.deal(address(vault), 2 ether);
        plan.actions[0] = _transferAction(address(0), firstRecipient, 1 ether);

        executor.execute(vault, plan, _sign(executor, plan, privateKey));

        ActionTypes.ActionPlan memory secondPlan = plan;
        secondPlan.nonce = 2;
        secondPlan.actions = new ActionTypes.Action[](1);
        secondPlan.actions[0] = _transferAction(
            address(0),
            secondRecipient,
            1 ether
        );
        executor.execute(
            vault,
            secondPlan,
            _sign(executor, secondPlan, privateKey)
        );

        assert(firstRecipient.balance == 1 ether);
        assert(secondRecipient.balance == 1 ether);
        assert(address(vault).balance == 0);
    }

    function test_failedPlanDoesNotConsumeNonce() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(3 ether);
        address firstRecipient = address(0xBEEF);
        address correctedRecipient = address(0xCAFE);
        RevertingReceiver receiver = new RevertingReceiver();
        vm.deal(address(vault), 3 ether);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), firstRecipient, 1 ether);
        plan.actions[1] = _transferAction(
            address(0),
            address(receiver),
            1 ether
        );
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(!executor.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(firstRecipient.balance == 0);
        assert(address(vault).balance == 3 ether);

        ActionTypes.ActionPlan memory correctedPlan = plan;
        correctedPlan.actions = new ActionTypes.Action[](2);
        correctedPlan.actions[0] = _transferAction(
            address(0),
            firstRecipient,
            1 ether
        );
        correctedPlan.actions[1] = _transferAction(
            address(0),
            correctedRecipient,
            1 ether
        );
        executor.execute(
            vault,
            correctedPlan,
            _sign(executor, correctedPlan, privateKey)
        );

        assert(
            executor.nonceUsed(
                correctedPlan.mandateId,
                correctedPlan.agent,
                correctedPlan.nonce
            )
        );
        assert(firstRecipient.balance == 1 ether);
        assert(correctedRecipient.balance == 1 ether);
        assert(address(vault).balance == 1 ether);
    }

    function test_normalExecutionUsesTightenedAndLoosenedMandateRules() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        MandateRegistry registry = executor.evaluator().registry();
        registry.updateMandate(
            plan.mandateId,
            _rules(0.5 ether, 0),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );
        vm.deal(address(vault), 1 ether);

        bool tightenedReverted;
        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            tightenedReverted = true;
        }

        registry.updateMandate(
            plan.mandateId,
            _rules(1 ether, 0),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );
        executor.execute(vault, plan, _sign(executor, plan, privateKey));

        assert(tightenedReverted);
        assert(address(0xBEEF).balance == 1 ether);
        assert(address(vault).balance == 0);
        assert(registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
    }

    function test_normalExecutionPreflightDenyDoesNotConsumeNonce() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        MandateRegistry registry = executor.evaluator().registry();
        registry.updateMandate(
            plan.mandateId,
            _rules(0, 0),
            MandateRegistry.PreflightRules({
                minNativeBalance: 2 ether,
                escalateNativeBalance: false
            })
        );
        vm.deal(address(vault), 2 ether);

        bool reverted;
        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(!registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(address(vault).balance == 2 ether);
        assert(address(0xBEEF).balance == 0);
    }

    function test_reentrantNormalPlanCannotBypassPreflightReserve() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        MandateRegistry registry = executor.evaluator().registry();
        registry.updateMandate(
            plan.mandateId,
            _rules(0, 0),
            MandateRegistry.PreflightRules({
                minNativeBalance: 1 ether,
                escalateNativeBalance: false
            })
        );

        ReentrantNativeRecipient recipient = new ReentrantNativeRecipient();
        ActionTypes.ActionPlan memory nestedPlan = ActionTypes.ActionPlan({
            mandateId: plan.mandateId,
            agent: plan.agent,
            nonce: 2,
            deadline: plan.deadline,
            actions: new ActionTypes.Action[](1)
        });
        nestedPlan.actions[0] = _transferAction(
            address(0),
            address(0xCAFE),
            1 ether
        );
        bytes memory nestedSignature = _sign(executor, nestedPlan, privateKey);
        recipient.configure(
            address(executor),
            abi.encodeCall(
                VaultExecutor.execute,
                (vault, nestedPlan, nestedSignature)
            )
        );

        plan.actions[0] = _transferAction(
            address(0),
            address(recipient),
            1 ether
        );
        vm.deal(address(vault), 2 ether);

        executor.execute(vault, plan, _sign(executor, plan, privateKey));

        assert(recipient.attempted());
        assert(recipient.blocked());
        assert(address(0xCAFE).balance == 0);
        assert(address(vault).balance == 1 ether);
        assert(registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(
            !registry.nonceUsed(
                nestedPlan.mandateId,
                nestedPlan.agent,
                nestedPlan.nonce
            )
        );
    }

    function test_normalExecutionIsBlockedAfterMandateRevocation() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        MandateRegistry registry = executor.evaluator().registry();
        registry.revokeMandate(plan.mandateId);
        vm.deal(address(vault), 1 ether);

        bool reverted;
        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(!registry.nonceUsed(plan.mandateId, plan.agent, plan.nonce));
        assert(address(0xBEEF).balance == 0);
        assert(address(vault).balance == 1 ether);
    }

    function test_acceptsTokenCallWithNoReturnData() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        NoReturnToken token = new NoReturnToken();
        plan.actions[0] = _transferAction(
            address(token),
            address(0xBEEF),
            1 ether
        );
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(!reverted);
    }

    function test_rejectsFalseTokenReturn() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        FalseReturnToken token = new FalseReturnToken();
        plan.actions[0] = _transferAction(
            address(token),
            address(0xBEEF),
            1 ether
        );
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function test_rejectsMalformedTokenReturn() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        MalformedReturnToken token = new MalformedReturnToken();
        plan.actions[0] = _transferAction(
            address(token),
            address(0xBEEF),
            1 ether
        );
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function test_rejectsTokenTargetWithoutCode() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        plan.actions[0] = _transferAction(
            address(0xCAFE),
            address(0xBEEF),
            1 ether
        );
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function test_deniedPlanNeverCallsVault() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether);
        address recipient = address(0xBEEF);
        vm.deal(address(vault), 2 ether);
        plan.actions[0] = _transferAction(address(0), recipient, 2 ether);
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(recipient.balance == 0);
        assert(address(vault).balance == 2 ether);
    }

    function test_revertsWholePlanWhenLaterActionFails() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(2 ether);
        address recipient = address(0xBEEF);
        RevertingReceiver receiver = new RevertingReceiver();
        vm.deal(address(vault), 2 ether);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), recipient, 1 ether);
        plan.actions[1] = _transferAction(
            address(0),
            address(receiver),
            1 ether
        );
        bool reverted;

        try
            executor.execute(vault, plan, _sign(executor, plan, privateKey))
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(recipient.balance == 0);
        assert(address(vault).balance == 2 ether);
    }

    function test_rejectsPlanForDifferentVault() public {
        (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(1 ether);
        Vault otherVault = new Vault();
        bool reverted;

        try
            executor.execute(
                otherVault,
                plan,
                _sign(executor, plan, privateKey)
            )
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(vault.authority() == address(executor));
        assert(otherVault.authority() == address(0));
    }

    function test_rejectsInvalidEvaluator() public {
        bool reverted;

        try new VaultExecutor(address(0), address(0)) {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function _setup(
        uint256 maxNativeAmount
    )
        private
        returns (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(maxNativeAmount, 0),
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

    function _setupWithUsd(
        uint256 maxNativeAmount,
        uint256 maxUsdAmount,
        uint256 usdAmount
    )
        private
        returns (
            Vault vault,
            VaultExecutor executor,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            _rules(maxNativeAmount, maxUsdAmount),
            MandateRegistry.PreflightRules({
                minNativeBalance: 0,
                escalateNativeBalance: false
            })
        );
        ExecutorMockUsdValueProvider provider = new ExecutorMockUsdValueProvider(
                usdAmount,
                true
            );
        MandateEvaluator evaluator = new MandateEvaluator(
            address(registry),
            address(provider),
            false
        );
        EscalationManager manager = new EscalationManager(address(evaluator));
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
        uint256 maxUsdAmount
    ) private pure returns (MandateRegistry.MandateRules memory) {
        return
            MandateRegistry.MandateRules({
                minNativeAmount: 0,
                maxNativeAmount: maxNativeAmount,
                escalateNativeAmount: false,
                minUsdAmount: 0,
                maxUsdAmount: maxUsdAmount,
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

    function _sign(
        VaultExecutor executor,
        ActionTypes.ActionPlan memory plan,
        uint256 privateKey
    ) private returns (bytes memory signature) {
        bytes32 digest = ActionSignature.digest(
            plan,
            address(executor.evaluator()),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
