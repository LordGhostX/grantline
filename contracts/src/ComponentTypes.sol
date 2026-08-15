// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library ComponentTypes {
    bytes32 internal constant GRANTLINE = keccak256("GRANTLINE");
    bytes32 internal constant REGISTRY = keccak256("REGISTRY");
    bytes32 internal constant EVALUATOR = keccak256("EVALUATOR");
    bytes32 internal constant ESCALATION_MANAGER = keccak256("ESCALATION_MANAGER");
    bytes32 internal constant EXECUTOR = keccak256("EXECUTOR");
    bytes32 internal constant VAULT_FACTORY = keccak256("VAULT_FACTORY");
    bytes32 internal constant VAULT = keccak256("VAULT");
}
