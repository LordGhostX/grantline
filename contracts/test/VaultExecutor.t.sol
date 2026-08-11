// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";

interface ExecutorVm {
    function addr(uint256 privateKey) external returns (address);

    function deal(address account, uint256 newBalance) external;

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

contract VaultExecutorTest {
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

        executor.execute(vault, plan, _sign(executor, plan, privateKey));

        assert(token.balanceOf(address(vault)) == 60 ether);
        assert(token.balanceOf(recipient) == 40 ether);
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

        try new VaultExecutor(address(0)) {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function _setup(
        uint256 transactionLimit
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
            transactionLimit
        );
        MandateEvaluator evaluator = new MandateEvaluator(address(registry));
        executor = new VaultExecutor(address(evaluator));
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
