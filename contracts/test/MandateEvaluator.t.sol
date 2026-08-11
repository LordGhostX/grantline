// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";

interface EvaluatorVm {
    function addr(uint256 privateKey) external returns (address);

    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external returns (uint8 v, bytes32 r, bytes32 s);

    function warp(uint256 timestamp) external;
}

contract MandateEvaluatorTest {
    EvaluatorVm private constant vm =
        EvaluatorVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_evaluatesSignedNativePlanUnderAggregateLimit() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 3 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 4 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.passed);
        assert(result.failureCode == MandateEvaluator.FailureCode.NONE);
        assert(result.failedActionIndex == type(uint256).max);
        assert(result.nativeAmount == 7 ether);
    }

    function test_rejectsPlanWhenAggregateNativeAmountExceedsLimit() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions = new ActionTypes.Action[](2);
        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 6 ether);
        plan.actions[1] = _transferAction(address(0), address(0xD00D), 5 ether);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(!result.passed);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.TRANSACTION_LIMIT_EXCEEDED
        );
        assert(result.failedActionIndex == 1);
        assert(result.nativeAmount == 11 ether);
    }

    function test_disabledLimitAllowsTokenTransfer() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(0);
        plan.actions[0] = _transferAction(
            address(0xCAFE),
            address(0xBEEF),
            1_000_000 ether
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.passed);
        assert(result.nativeAmount == 0);
    }

    function test_enabledLimitDoesNotRejectTokenTransferWithoutAssetGuard()
        public
    {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0] = _transferAction(
            address(0xCAFE),
            address(0xBEEF),
            1_000_000 ether
        );

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.passed);
        assert(result.nativeAmount == 0);
    }

    function test_doesNotRequireTransferVersionOne() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0] = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: 2,
            parameters: abi.encode(
                ActionTypes.TransferParameters({
                    asset: address(0),
                    recipient: address(0xBEEF),
                    amount: 1 ether
                })
            )
        });

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(result.passed);
        assert(result.nativeAmount == 1 ether);
    }

    function test_rejectsMandateAgentSignatureAndDeadlineFailures() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.agent = address(0xCAFE);

        MandateEvaluator.EvaluationResult memory agentResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(!agentResult.passed);
        assert(
            agentResult.failureCode ==
                MandateEvaluator.FailureCode.AGENT_MISMATCH
        );

        plan.agent = vm.addr(privateKey);
        plan.deadline = 1;
        vm.warp(2);
        MandateEvaluator.EvaluationResult memory deadlineResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(!deadlineResult.passed);
        assert(
            deadlineResult.failureCode == MandateEvaluator.FailureCode.EXPIRED
        );
    }

    function test_rejectsInvalidActionShape() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0] = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: 0,
            parameters: hex"01"
        });

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(!result.passed);
        assert(
            result.failureCode == MandateEvaluator.FailureCode.INVALID_ACTION
        );
        assert(result.failedActionIndex == 0);
    }

    function test_rejectsInvalidTransferParameters() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions[0].parameters = hex"01";

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(!result.passed);
        assert(
            result.failureCode ==
                MandateEvaluator.FailureCode.INVALID_ACTION_PARAMETERS
        );
        assert(result.failedActionIndex == 0);
    }

    function test_rejectsEmptyPlan() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        plan.actions = new ActionTypes.Action[](0);

        MandateEvaluator.EvaluationResult memory result = evaluator.evaluate(
            plan,
            _sign(evaluator, plan, privateKey)
        );

        assert(!result.passed);
        assert(result.failureCode == MandateEvaluator.FailureCode.EMPTY_PLAN);
    }

    function test_rejectsInvalidSignatureRecipientAndAmount() public {
        (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        ) = _setup(10 ether);
        MandateEvaluator.EvaluationResult memory signatureResult = evaluator
            .evaluate(plan, hex"");

        assert(!signatureResult.passed);
        assert(
            signatureResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_SIGNATURE
        );

        plan.actions[0] = _transferAction(address(0), address(0), 1 ether);
        MandateEvaluator.EvaluationResult memory recipientResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(!recipientResult.passed);
        assert(
            recipientResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_RECIPIENT
        );

        plan.actions[0] = _transferAction(address(0), address(0xBEEF), 0);
        MandateEvaluator.EvaluationResult memory amountResult = evaluator
            .evaluate(plan, _sign(evaluator, plan, privateKey));
        assert(!amountResult.passed);
        assert(
            amountResult.failureCode ==
                MandateEvaluator.FailureCode.INVALID_AMOUNT
        );
    }

    function test_rejectsUnknownAndRevokedMandates() public {
        MandateRegistry registry = new MandateRegistry();
        MandateEvaluator evaluator = new MandateEvaluator(address(registry));
        ActionTypes.ActionPlan memory unknownPlan = _plan(
            1,
            address(0xA11CE),
            1 ether,
            0
        );

        MandateEvaluator.EvaluationResult memory unknownResult = evaluator
            .evaluate(unknownPlan, hex"");
        assert(!unknownResult.passed);
        assert(
            unknownResult.failureCode ==
                MandateEvaluator.FailureCode.MANDATE_NOT_FOUND
        );

        Vault vault = new Vault();
        uint256 mandateId = registry.createMandate(
            address(vault),
            address(0xA11CE),
            10 ether
        );
        registry.revokeMandate(mandateId);
        ActionTypes.ActionPlan memory revokedPlan = _plan(
            mandateId,
            address(0xA11CE),
            1 ether,
            0
        );

        MandateEvaluator.EvaluationResult memory revokedResult = evaluator
            .evaluate(revokedPlan, hex"");
        assert(!revokedResult.passed);
        assert(
            revokedResult.failureCode ==
                MandateEvaluator.FailureCode.MANDATE_INACTIVE
        );
    }

    function _setup(
        uint256 transactionLimit
    )
        private
        returns (
            MandateEvaluator evaluator,
            ActionTypes.ActionPlan memory plan,
            uint256 privateKey
        )
    {
        privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        Vault vault = new Vault();
        MandateRegistry registry = new MandateRegistry();
        uint256 mandateId = registry.createMandate(
            address(vault),
            agent,
            transactionLimit
        );
        evaluator = new MandateEvaluator(address(registry));
        plan = _plan(mandateId, agent, 1 ether, 0);
    }

    function _plan(
        uint256 mandateId,
        address agent,
        uint256 amount,
        uint256 deadline
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = _transferAction(address(0), address(0xBEEF), amount);
        return
            ActionTypes.ActionPlan({
                mandateId: mandateId,
                agent: agent,
                nonce: 1,
                deadline: deadline,
                actions: actions
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
