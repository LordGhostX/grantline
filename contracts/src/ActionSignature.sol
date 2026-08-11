// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "./ActionTypes.sol";

library ActionSignature {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 internal constant ACTION_TYPEHASH =
        keccak256("Action(uint8 actionType,uint8 version,bytes parameters)");
    bytes32 internal constant ACTION_PLAN_TYPEHASH =
        keccak256(
            "ActionPlan(uint256 mandateId,address agent,uint256 nonce,uint256 deadline,Action[] actions)Action(uint8 actionType,uint8 version,bytes parameters)"
        );
    bytes32 internal constant NAME_HASH = keccak256("Grantline");
    bytes32 internal constant VERSION_HASH = keccak256("1");
    uint256 internal constant SECP256K1N_HALF_ORDER =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    function domainSeparator(
        address verifyingContract,
        uint256 chainId
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPEHASH,
                    NAME_HASH,
                    VERSION_HASH,
                    chainId,
                    verifyingContract
                )
            );
    }

    function digest(
        ActionTypes.ActionPlan memory plan,
        address verifyingContract,
        uint256 chainId
    ) internal pure returns (bytes32) {
        bytes32 structHash = hashActionPlan(plan);
        bytes32 separator = domainSeparator(verifyingContract, chainId);
        return keccak256(abi.encodePacked("\x19\x01", separator, structHash));
    }

    function digest(
        ActionTypes.ActionPlan memory plan,
        address verifyingContract
    ) internal view returns (bytes32) {
        return digest(plan, verifyingContract, block.chainid);
    }

    function hashActionPlan(
        ActionTypes.ActionPlan memory plan
    ) internal pure returns (bytes32) {
        bytes32[] memory actionHashes = new bytes32[](plan.actions.length);
        for (uint256 index; index < plan.actions.length; index++) {
            actionHashes[index] = hashAction(plan.actions[index]);
        }

        return
            keccak256(
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

    function hashAction(
        ActionTypes.Action memory action
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ACTION_TYPEHASH,
                    uint8(action.actionType),
                    action.version,
                    keccak256(action.parameters)
                )
            );
    }

    function recoverSigner(
        bytes32 actionDigest,
        bytes memory signature
    ) internal pure returns (address signer) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if ((v != 27 && v != 28) || uint256(s) > SECP256K1N_HALF_ORDER)
            return address(0);
        return ecrecover(actionDigest, v, r, s);
    }

    function isValid(
        ActionTypes.ActionPlan memory plan,
        address verifyingContract,
        uint256 chainId,
        bytes memory signature
    ) internal pure returns (bool) {
        if (plan.agent == address(0)) return false;
        return
            recoverSigner(
                digest(plan, verifyingContract, chainId),
                signature
            ) == plan.agent;
    }
}
