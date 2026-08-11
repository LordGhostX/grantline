// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";

contract ActionTypesTest {
    function test_roundTripsNativeTransferPlan() public pure {
        ActionTypes.TransferParameters memory transfer = ActionTypes
            .TransferParameters({
                asset: address(0),
                recipient: address(0xBEEF),
                amount: 1 ether
            });
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: 1,
            parameters: abi.encode(transfer)
        });
        ActionTypes.ActionPlan memory plan = ActionTypes.ActionPlan({
            mandateId: 7,
            agent: address(0xA11CE),
            nonce: 0,
            deadline: 0,
            actions: actions
        });

        ActionTypes.ActionPlan memory decodedPlan = abi.decode(
            abi.encode(plan),
            (ActionTypes.ActionPlan)
        );
        ActionTypes.TransferParameters memory decodedTransfer = abi.decode(
            decodedPlan.actions[0].parameters,
            (ActionTypes.TransferParameters)
        );

        assert(decodedPlan.mandateId == 7);
        assert(decodedPlan.agent == address(0xA11CE));
        assert(decodedPlan.nonce == 0);
        assert(decodedPlan.deadline == 0);
        assert(decodedPlan.actions.length == 1);
        assert(
            decodedPlan.actions[0].actionType == ActionTypes.ActionType.TRANSFER
        );
        assert(decodedPlan.actions[0].version == 1);
        assert(decodedTransfer.asset == address(0));
        assert(decodedTransfer.recipient == address(0xBEEF));
        assert(decodedTransfer.amount == 1 ether);
    }

    function test_roundTripsTokenTransferParameters() public pure {
        address token = address(0xCAFE);
        ActionTypes.TransferParameters memory transfer = ActionTypes
            .TransferParameters({
                asset: token,
                recipient: address(0xBEEF),
                amount: 250 ether
            });

        ActionTypes.TransferParameters memory decodedTransfer = abi.decode(
            abi.encode(transfer),
            (ActionTypes.TransferParameters)
        );

        assert(decodedTransfer.asset == token);
        assert(decodedTransfer.recipient == address(0xBEEF));
        assert(decodedTransfer.amount == 250 ether);
    }

    function test_preservesOrderedActionsInOnePlan() public pure {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), address(0xBEEF), 1 ether);
        actions[1] = _transferAction(address(0xCAFE), address(0xD00D), 2 ether);

        ActionTypes.ActionPlan memory plan = ActionTypes.ActionPlan({
            mandateId: 3,
            agent: address(0xA11CE),
            nonce: 11,
            deadline: 1_900_000_000,
            actions: actions
        });
        ActionTypes.ActionPlan memory decodedPlan = abi.decode(
            abi.encode(plan),
            (ActionTypes.ActionPlan)
        );

        ActionTypes.TransferParameters memory first = abi.decode(
            decodedPlan.actions[0].parameters,
            (ActionTypes.TransferParameters)
        );
        ActionTypes.TransferParameters memory second = abi.decode(
            decodedPlan.actions[1].parameters,
            (ActionTypes.TransferParameters)
        );

        assert(decodedPlan.actions.length == 2);
        assert(decodedPlan.nonce == 11);
        assert(decodedPlan.deadline == 1_900_000_000);
        assert(first.asset == address(0));
        assert(first.recipient == address(0xBEEF));
        assert(first.amount == 1 ether);
        assert(second.asset == address(0xCAFE));
        assert(second.recipient == address(0xD00D));
        assert(second.amount == 2 ether);
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
}
