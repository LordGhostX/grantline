// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "./ActionTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";

interface IComponent {
    function componentType() external view returns (bytes32);
}

interface IOwnable2Step {
    function owner() external view returns (address);

    function pendingOwner() external view returns (address);
}

interface IGrantlineContext is IComponent {
    function moduleAddress(bytes32 key) external view returns (address);

    function controllerOf(address vault) external view returns (address);

    function isController(address vault, address account) external view returns (bool);

    function actionDigest(ActionTypes.ActionPlan calldata plan) external view returns (bytes32);
}

interface IGrantlineAdminTarget {
    function configureModules(
        address registryAddress,
        address evaluatorAddress,
        address escalationManagerAddress,
        address executorAddress,
        address vaultFactoryAddress
    ) external;

    function adminSetVaultController(address vault, address newController) external;

    function adminRecordVaultUpgrade(address vault, address implementation, uint64 version) external;

    function isRegisteredVault(address vault) external view returns (bool);

    function registry() external view returns (address);

    function evaluator() external view returns (address);

    function escalationManager() external view returns (address);

    function executor() external view returns (address);

    function vaultFactory() external view returns (address);

    function configured() external view returns (bool);
}

interface IGrantlineAdmin {
    function grantline() external view returns (address);
}

interface IModule is IComponent {
    function grantline() external view returns (address);

    function version() external pure returns (uint64);
}

interface IRegistry is IModule {
    function registerVault(address vault) external;

    function createMandate(
        address vault,
        address actor,
        address agent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external returns (uint256 mandateId);

    function createChildMandate(
        uint256 parentMandateId,
        address actor,
        address childAgent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external returns (uint256 mandateId);

    function updateMandate(
        uint256 mandateId,
        address actor,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external;

    function revokeMandate(uint256 mandateId, address actor) external;

    function getMandate(uint256 mandateId) external view returns (GrantlineTypes.Mandate memory);

    function getLineage(uint256 mandateId) external view returns (uint256[] memory);

    function getEffectiveRules(uint256 mandateId) external view returns (GrantlineTypes.MandateRules memory);

    function getEffectivePreflightRules(uint256 mandateId) external view returns (GrantlineTypes.PreflightRules memory);

    function getEffectiveValidityWindow(uint256 mandateId) external view returns (uint64 validAfter, uint64 validUntil);

    function isLineageActive(uint256 mandateId) external view returns (bool);

    function isLineagePaused(uint256 mandateId) external view returns (bool);

    function isLineageRevoked(uint256 mandateId) external view returns (bool);

    function pauseMandate(uint256 mandateId, address actor) external;

    function unpauseMandate(uint256 mandateId, address actor) external;

    function mandateCount() external view returns (uint256);

    function nonceUsed(uint256 mandateId, address agent, uint256 nonce) external view returns (bool);

    function reservedDigest(uint256 mandateId, address agent, uint256 nonce) external view returns (bytes32);

    function consumeNonce(uint256 mandateId, address agent, uint256 nonce) external;

    function reserveNonce(uint256 mandateId, address agent, uint256 nonce, bytes32 digest) external;

    function consumeReservedNonce(uint256 mandateId, address agent, uint256 nonce, bytes32 digest) external;
}

interface IEvaluator is IModule {
    function registry() external view returns (address);

    function evaluate(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest)
        external
        view
        returns (GrantlineTypes.EvaluationResult memory);
}

interface IEscalationManager is IModule {
    function evaluator() external view returns (address);

    function registry() external view returns (address);

    function submit(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest, address submittedBy)
        external;

    function approve(bytes32 digest, address controller) external;

    function deny(bytes32 digest, address controller) external;

    function markExecuted(bytes32 digest) external;

    function getEscalation(bytes32 digest) external view returns (GrantlineTypes.Escalation memory);
}

interface IExecutor is IModule {
    function evaluator() external view returns (address);

    function escalationManager() external view returns (address);

    function registry() external view returns (address);

    function execute(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest) external;

    function executeEscalated(bytes32 digest) external;
}

interface IVaultFactory is IModule {
    function executor() external view returns (address);

    function upgradeAuthority() external view returns (address);

    function createVault(address controller) external returns (address vault);

    function validateVaultImplementation(address implementation, uint64 implementationVersion) external;

    function setVaultImplementation(address implementation, uint64 implementationVersion) external;

    function vaultImplementation() external view returns (address);

    function vaultImplementationVersion() external view returns (uint64);

    function isVault(address vault) external view returns (bool);

    function vaultCount() external view returns (uint256);

    function vaultAt(uint256 index) external view returns (address);
}

interface IVault is IComponent {
    function initialize(address grantline, address authorityAddress, address upgradeAuthorityAddress) external;

    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);

    function pauseInterfaceVersion() external pure returns (uint64);

    function owner() external view returns (address);

    function authority() external view returns (address);

    function upgradeAuthority() external view returns (address);

    function version() external pure returns (uint64);

    function depositNative(address from) external payable;

    function depositTokenFrom(address from, address token, uint256 amount) external;

    function withdrawNative(address payable recipient, uint256 amount) external;

    function withdrawToken(address token, address recipient, uint256 amount) external;

    function tokenBalance(address token) external view returns (uint256);

    function execute(address target, uint256 value, bytes calldata data)
        external
        returns (bool success, bytes memory result);
}

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}
