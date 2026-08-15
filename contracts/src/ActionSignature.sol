// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "./ActionTypes.sol";

library ActionSignature {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant ACTION_TYPEHASH = keccak256("Action(uint8 actionType,uint8 version,bytes parameters)");
    bytes32 internal constant ACTION_PLAN_TYPEHASH = keccak256(
        "ActionPlan(uint256 mandateId,address agent,uint256 nonce,uint256 deadline,Action[] actions)Action(uint8 actionType,uint8 version,bytes parameters)"
    );

    function hashActionPlan(ActionTypes.ActionPlan memory plan) internal pure returns (bytes32) {
        bytes32[] memory actionHashes = new bytes32[](plan.actions.length);
        for (uint256 index; index < plan.actions.length; index++) {
            actionHashes[index] = hashAction(plan.actions[index]);
        }

        return keccak256(
            abi.encode(
                ACTION_PLAN_TYPEHASH,
                plan.mandateId,
                plan.agent,
                plan.nonce,
                plan.deadline,
                keccak256(abi.encodePacked(actionHashes))
            )
        );
    }

    function hashAction(ActionTypes.Action memory action) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(ACTION_TYPEHASH, uint8(action.actionType), action.version, keccak256(action.parameters))
            );
    }
}
