// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";
import {IGrantlineContext, IEvaluator, IRegistry} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

interface IVaultIdentity {
    function owner() external view returns (address);

    function authority() external view returns (address);
}

contract MandateRegistry is Initializable, GrantlineOwnable2StepUpgradeable, UUPSUpgradeable, IRegistry {
    bytes32 public constant EXECUTOR_MODULE = keccak256("EXECUTOR");
    bytes32 public constant ESCALATION_MANAGER_MODULE = keccak256("ESCALATION_MANAGER");
    bytes32 public constant EVALUATOR_MODULE = keccak256("EVALUATOR");

    uint8 public constant MAX_DELEGATION_DEPTH = 2;

    error InvalidAddress();
    error InvalidVault();
    error VaultNotRegistered(address vault);
    error MandateNotActive(uint256 mandateId);
    error MandateNotPaused(uint256 mandateId);
    error MandateNotFound(uint256 mandateId);
    error MandateAgentMismatch(uint256 mandateId, address agent);
    error InvalidReservationDigest();
    error NonceAlreadyUsed(uint256 mandateId, address agent, uint256 nonce);
    error NonceReserved(uint256 mandateId, address agent, uint256 nonce, bytes32 digest);
    error NonceReservationMismatch(
        uint256 mandateId, address agent, uint256 nonce, bytes32 expectedDigest, bytes32 reservedDigest
    );
    error InvalidNativeAmountRange(uint256 minimum, uint256 maximum);
    error InvalidNativeUsdRange(uint256 minimum, uint256 maximum);
    error NativeUsdValuationUnsupported();
    error NativeUsdThresholdTooLarge(uint256 value);
    error InvalidValidityWindow(uint64 validAfter, uint64 validUntil);
    error NotGrantline(address caller);
    error NotExecutor(address caller);
    error NotEscalationManager(address caller);
    error NotController(uint256 mandateId, address caller);
    error MandateNotDelegatable(uint256 mandateId);
    error DelegationDepthExceeded(uint256 parentMandateId, uint8 depth);
    error InvalidDelegationAgent(address parentAgent, address childAgent);
    error NotParentAgent(uint256 mandateId, address caller);
    error NotMandateAdministrator(uint256 mandateId, address caller);
    error NotNonceCanceller(uint256 mandateId, address caller);
    error MandateLineageInactive(uint256 mandateId, uint256 inactiveAncestorId);
    error ChildRulesExceedParent(uint256 parentMandateId);
    error ChildPreflightRulesExceedParent(uint256 parentMandateId);

    event VaultRegistered(address indexed vault);
    event MandateCreated(
        uint256 indexed mandateId,
        address indexed vault,
        address indexed agent,
        uint256 parentMandateId,
        uint8 delegationDepth,
        GrantlineTypes.MandateRules rules,
        GrantlineTypes.PreflightRules preflightRules,
        uint64 validAfter,
        uint64 validUntil,
        address createdBy,
        uint64 createdAt
    );
    event MandateUpdated(
        uint256 indexed mandateId,
        GrantlineTypes.MandateRules rules,
        GrantlineTypes.PreflightRules preflightRules,
        uint64 validAfter,
        uint64 validUntil,
        address indexed updatedBy,
        uint64 updatedAt
    );
    event MandateRevoked(uint256 indexed mandateId, address indexed revokedBy, uint64 revokedAt);
    event MandatePaused(uint256 indexed mandateId, address indexed pausedBy, uint64 pausedAt);
    event MandateUnpaused(uint256 indexed mandateId, address indexed unpausedBy, uint64 unpausedAt);
    event NonceReservationCreated(
        uint256 indexed mandateId, address indexed agent, uint256 indexed nonce, bytes32 digest
    );
    event NonceReservationConsumed(
        uint256 indexed mandateId, address indexed agent, uint256 indexed nonce, bytes32 digest
    );

    address public grantline;
    mapping(address => bool) public isRegisteredVault;
    mapping(uint256 => GrantlineTypes.Mandate) private _mandates;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public override nonceUsed;
    mapping(uint256 => mapping(address => mapping(uint256 => bytes32))) public override reservedDigest;
    uint256 public override mandateCount;

    constructor() {
        _disableInitializers();
    }

    function initialize(address grantlineAddress, address moduleOwnerAddress) external initializer {
        if (grantlineAddress == address(0)) revert InvalidAddress();
        if (moduleOwnerAddress == address(0) || moduleOwnerAddress.code.length == 0) revert InvalidAddress();
        grantline = grantlineAddress;
        __Ownable_init(moduleOwnerAddress);
        __Ownable2Step_init();
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.REGISTRY;
    }

    function registerVault(address vault) external {
        _onlyGrantline();
        if (vault == address(0) || vault.code.length == 0) {
            revert InvalidVault();
        }
        address expectedAuthority = IGrantlineContext(grantline).moduleAddress(EXECUTOR_MODULE);
        try IVaultIdentity(vault).owner() returns (address vaultOwner) {
            if (vaultOwner != grantline) revert InvalidVault();
        } catch {
            revert InvalidVault();
        }
        try IVaultIdentity(vault).authority() returns (address authority) {
            if (expectedAuthority == address(0) || authority != expectedAuthority) {
                revert InvalidVault();
            }
        } catch {
            revert InvalidVault();
        }
        isRegisteredVault[vault] = true;
        emit VaultRegistered(vault);
    }

    function createMandate(
        address vault,
        address actor,
        address agent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external returns (uint256 mandateId) {
        _onlyGrantline();
        _requireController(vault, actor);
        if (agent == address(0)) revert InvalidAddress();
        _validateRules(rules);
        _validatePreflightRules(preflightRules);
        _validateValidityWindow(validAfter, validUntil);

        mandateId = ++mandateCount;
        uint64 createdAt = uint64(block.timestamp);
        _mandates[mandateId] = GrantlineTypes.Mandate({
            id: mandateId,
            vault: vault,
            agent: agent,
            parentMandateId: 0,
            delegationDepth: 0,
            status: GrantlineTypes.MandateStatus.ACTIVE,
            rules: rules,
            preflightRules: preflightRules,
            validAfter: validAfter,
            validUntil: validUntil,
            createdAt: createdAt,
            revokedAt: 0
        });

        emit MandateCreated(
            mandateId, vault, agent, 0, 0, rules, preflightRules, validAfter, validUntil, actor, createdAt
        );
    }

    function createChildMandate(
        uint256 parentMandateId,
        address actor,
        address childAgent,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external returns (uint256 mandateId) {
        _onlyGrantline();
        GrantlineTypes.Mandate storage parent = _activeMandate(parentMandateId);
        if (parent.agent != actor) {
            revert NotParentAgent(parentMandateId, actor);
        }
        _requireActiveLineage(parentMandateId);

        GrantlineTypes.MandateRules memory parentRules = _effectiveRules(parentMandateId);
        GrantlineTypes.PreflightRules memory parentPreflightRules = _effectivePreflightRules(parentMandateId);
        if (!parentRules.canDelegate) {
            revert MandateNotDelegatable(parentMandateId);
        }
        if (childAgent == address(0)) revert InvalidAddress();
        if (childAgent == parent.agent) {
            revert InvalidDelegationAgent(parent.agent, childAgent);
        }

        uint8 childDepth = parent.delegationDepth + 1;
        if (childDepth > MAX_DELEGATION_DEPTH) {
            revert DelegationDepthExceeded(parentMandateId, childDepth);
        }
        if (childDepth == MAX_DELEGATION_DEPTH && rules.canDelegate) {
            revert DelegationDepthExceeded(parentMandateId, childDepth);
        }

        _validateRules(rules);
        _validatePreflightRules(preflightRules);
        _validateValidityWindow(validAfter, validUntil);
        _validateChildRules(parentMandateId, parentRules, rules);
        _validateChildPreflightRules(parentMandateId, parentPreflightRules, preflightRules);

        mandateId = ++mandateCount;
        uint64 createdAt = uint64(block.timestamp);
        _mandates[mandateId] = GrantlineTypes.Mandate({
            id: mandateId,
            vault: parent.vault,
            agent: childAgent,
            parentMandateId: parentMandateId,
            delegationDepth: childDepth,
            status: GrantlineTypes.MandateStatus.ACTIVE,
            rules: rules,
            preflightRules: preflightRules,
            validAfter: validAfter,
            validUntil: validUntil,
            createdAt: createdAt,
            revokedAt: 0
        });

        emit MandateCreated(
            mandateId,
            parent.vault,
            childAgent,
            parentMandateId,
            childDepth,
            rules,
            preflightRules,
            validAfter,
            validUntil,
            actor,
            createdAt
        );
    }

    function updateMandate(
        uint256 mandateId,
        address actor,
        GrantlineTypes.MandateRules calldata rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil
    ) external {
        _onlyGrantline();
        GrantlineTypes.Mandate storage mandate = _editableMandate(mandateId);
        _requireMandateAdministrator(mandateId, mandate, actor);
        if (mandate.delegationDepth == MAX_DELEGATION_DEPTH) {
            GrantlineTypes.MandateRules memory normalized = rules;
            normalized.canDelegate = false;
            _updateMandate(mandateId, mandate, normalized, preflightRules, validAfter, validUntil, actor);
            return;
        }
        _updateMandate(mandateId, mandate, rules, preflightRules, validAfter, validUntil, actor);
    }

    function _updateMandate(
        uint256 mandateId,
        GrantlineTypes.Mandate storage mandate,
        GrantlineTypes.MandateRules memory rules,
        GrantlineTypes.PreflightRules calldata preflightRules,
        uint64 validAfter,
        uint64 validUntil,
        address actor
    ) private {
        _validateRules(rules);
        _validatePreflightRules(preflightRules);
        _validateValidityWindow(validAfter, validUntil);
        if (mandate.parentMandateId != 0) {
            _requireEditableLineage(mandate.parentMandateId);
            _validateChildRules(mandate.parentMandateId, _effectiveRules(mandate.parentMandateId), rules);
            _validateChildPreflightRules(
                mandate.parentMandateId, _effectivePreflightRules(mandate.parentMandateId), preflightRules
            );
        }

        mandate.rules = rules;
        mandate.preflightRules = preflightRules;
        mandate.validAfter = validAfter;
        mandate.validUntil = validUntil;
        emit MandateUpdated(mandateId, rules, preflightRules, validAfter, validUntil, actor, uint64(block.timestamp));
    }

    function revokeMandate(uint256 mandateId, address actor) external {
        _onlyGrantline();
        GrantlineTypes.Mandate storage mandate = _editableMandate(mandateId);
        _requireMandateAdministrator(mandateId, mandate, actor);
        uint64 revokedAt = uint64(block.timestamp);
        mandate.status = GrantlineTypes.MandateStatus.REVOKED;
        mandate.revokedAt = revokedAt;
        emit MandateRevoked(mandateId, actor, revokedAt);
    }

    function pauseMandate(uint256 mandateId, address actor) external override {
        _onlyGrantline();
        GrantlineTypes.Mandate storage mandate = _activeMandate(mandateId);
        _requireMandateAdministrator(mandateId, mandate, actor);
        mandate.status = GrantlineTypes.MandateStatus.PAUSED;
        emit MandatePaused(mandateId, actor, uint64(block.timestamp));
    }

    function unpauseMandate(uint256 mandateId, address actor) external override {
        _onlyGrantline();
        GrantlineTypes.Mandate storage mandate = _requireMandateExists(mandateId);
        if (mandate.status != GrantlineTypes.MandateStatus.PAUSED) {
            revert MandateNotPaused(mandateId);
        }
        _requireMandateAdministrator(mandateId, mandate, actor);
        mandate.status = GrantlineTypes.MandateStatus.ACTIVE;
        emit MandateUnpaused(mandateId, actor, uint64(block.timestamp));
    }

    function cancelNonce(uint256 mandateId, address actor, uint256 nonce) external override {
        _onlyGrantline();
        GrantlineTypes.Mandate storage mandate = _requireMandateExists(mandateId);
        _requireNonceCanceller(mandateId, mandate, actor);
        address agent = mandate.agent;
        _requireNonceUnused(mandateId, agent, nonce);
        bytes32 reservation = reservedDigest[mandateId][agent][nonce];
        if (reservation != bytes32(0)) {
            revert NonceReserved(mandateId, agent, nonce, reservation);
        }
        nonceUsed[mandateId][agent][nonce] = true;
    }

    function consumeNonce(uint256 mandateId, address agent, uint256 nonce) external override {
        _onlyExecutor();
        GrantlineTypes.Mandate storage mandate = _activeMandate(mandateId);
        _requireActiveLineage(mandateId);
        _requireMandateAgent(mandate, mandateId, agent);
        _requireNonceUnused(mandateId, agent, nonce);
        bytes32 reservation = reservedDigest[mandateId][agent][nonce];
        if (reservation != bytes32(0)) {
            revert NonceReserved(mandateId, agent, nonce, reservation);
        }
        nonceUsed[mandateId][agent][nonce] = true;
    }

    function reserveNonce(uint256 mandateId, address agent, uint256 nonce, bytes32 digest) external override {
        _onlyEscalationManager();
        if (digest == bytes32(0)) revert InvalidReservationDigest();
        GrantlineTypes.Mandate storage mandate = _activeMandate(mandateId);
        _requireActiveLineage(mandateId);
        _requireMandateAgent(mandate, mandateId, agent);
        _requireNonceUnused(mandateId, agent, nonce);
        bytes32 existingDigest = reservedDigest[mandateId][agent][nonce];
        if (existingDigest != bytes32(0)) {
            revert NonceReserved(mandateId, agent, nonce, existingDigest);
        }
        reservedDigest[mandateId][agent][nonce] = digest;
        emit NonceReservationCreated(mandateId, agent, nonce, digest);
    }

    function consumeReservedNonce(uint256 mandateId, address agent, uint256 nonce, bytes32 digest) external override {
        _onlyExecutor();
        if (digest == bytes32(0)) revert InvalidReservationDigest();
        GrantlineTypes.Mandate storage mandate = _activeMandate(mandateId);
        _requireActiveLineage(mandateId);
        _requireMandateAgent(mandate, mandateId, agent);
        _requireNonceUnused(mandateId, agent, nonce);
        bytes32 reservation = reservedDigest[mandateId][agent][nonce];
        if (reservation != digest) {
            revert NonceReservationMismatch(mandateId, agent, nonce, digest, reservation);
        }
        delete reservedDigest[mandateId][agent][nonce];
        nonceUsed[mandateId][agent][nonce] = true;
        emit NonceReservationConsumed(mandateId, agent, nonce, digest);
    }

    function getMandate(uint256 mandateId) external view override returns (GrantlineTypes.Mandate memory) {
        return _requireMandateExists(mandateId);
    }

    function getLineage(uint256 mandateId) external view override returns (uint256[] memory lineage) {
        _requireMandateExists(mandateId);
        uint256 length = uint256(_mandates[mandateId].delegationDepth) + 1;
        lineage = new uint256[](length);
        uint256 currentMandateId = mandateId;
        for (uint256 index = length; index > 0; index--) {
            lineage[index - 1] = currentMandateId;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
    }

    function getEffectiveRules(uint256 mandateId) external view override returns (GrantlineTypes.MandateRules memory) {
        _requireMandateExists(mandateId);
        _requireActiveLineage(mandateId);
        return _effectiveRules(mandateId);
    }

    function getEffectivePreflightRules(uint256 mandateId)
        external
        view
        override
        returns (GrantlineTypes.PreflightRules memory)
    {
        _requireMandateExists(mandateId);
        _requireActiveLineage(mandateId);
        return _effectivePreflightRules(mandateId);
    }

    function getEffectiveValidityWindow(uint256 mandateId)
        external
        view
        override
        returns (uint64 validAfter, uint64 validUntil)
    {
        _requireMandateExists(mandateId);
        return _effectiveValidityWindow(mandateId);
    }

    function isActive(uint256 mandateId) external view returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        return _mandates[mandateId].status == GrantlineTypes.MandateStatus.ACTIVE;
    }

    function isLineageActive(uint256 mandateId) external view override returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            if (_mandates[currentMandateId].status != GrantlineTypes.MandateStatus.ACTIVE) return false;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
        (uint64 validAfter, uint64 validUntil) = _effectiveValidityWindow(mandateId);
        return _isWithinValidityWindow(validAfter, validUntil);
    }

    function isLineagePaused(uint256 mandateId) external view override returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            if (_mandates[currentMandateId].status == GrantlineTypes.MandateStatus.PAUSED) return true;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
        return false;
    }

    function isLineageRevoked(uint256 mandateId) external view override returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            if (_mandates[currentMandateId].status == GrantlineTypes.MandateStatus.REVOKED) return true;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
        return false;
    }

    function _activeMandate(uint256 mandateId) private view returns (GrantlineTypes.Mandate storage mandate) {
        mandate = _requireMandateExists(mandateId);
        if (mandate.status != GrantlineTypes.MandateStatus.ACTIVE) {
            revert MandateNotActive(mandateId);
        }
    }

    function _editableMandate(uint256 mandateId) private view returns (GrantlineTypes.Mandate storage mandate) {
        mandate = _requireMandateExists(mandateId);
        if (mandate.status == GrantlineTypes.MandateStatus.REVOKED) {
            revert MandateNotActive(mandateId);
        }
    }

    function _requireMandateExists(uint256 mandateId) private view returns (GrantlineTypes.Mandate storage mandate) {
        if (mandateId == 0 || mandateId > mandateCount) {
            revert MandateNotFound(mandateId);
        }
        mandate = _mandates[mandateId];
    }

    function _requireActiveLineage(uint256 mandateId) private view {
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            GrantlineTypes.Mandate storage current = _mandates[currentMandateId];
            if (current.status != GrantlineTypes.MandateStatus.ACTIVE) {
                revert MandateLineageInactive(mandateId, currentMandateId);
            }
            currentMandateId = current.parentMandateId;
        }
        (uint64 validAfter, uint64 validUntil) = _effectiveValidityWindow(mandateId);
        if (!_isWithinValidityWindow(validAfter, validUntil)) {
            revert MandateLineageInactive(mandateId, mandateId);
        }
    }

    function _requireEditableLineage(uint256 mandateId) private view {
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            GrantlineTypes.Mandate storage current = _mandates[currentMandateId];
            if (current.status == GrantlineTypes.MandateStatus.REVOKED) {
                revert MandateLineageInactive(mandateId, currentMandateId);
            }
            currentMandateId = current.parentMandateId;
        }
    }

    function _effectiveRules(uint256 mandateId) private view returns (GrantlineTypes.MandateRules memory effective) {
        uint256 currentMandateId = mandateId;
        bool initialized;
        while (currentMandateId != 0) {
            GrantlineTypes.Mandate storage current = _mandates[currentMandateId];
            if (!initialized) {
                effective = current.rules;
                initialized = true;
            } else {
                if (current.rules.minNativeAmount > effective.minNativeAmount) {
                    effective.minNativeAmount = current.rules.minNativeAmount;
                }
                if (
                    current.rules.maxNativeAmount != 0
                        && (effective.maxNativeAmount == 0 || current.rules.maxNativeAmount < effective.maxNativeAmount)
                ) {
                    effective.maxNativeAmount = current.rules.maxNativeAmount;
                }
                if (current.rules.minNativeUsd > effective.minNativeUsd) {
                    effective.minNativeUsd = current.rules.minNativeUsd;
                }
                if (
                    current.rules.maxNativeUsd != 0
                        && (effective.maxNativeUsd == 0 || current.rules.maxNativeUsd < effective.maxNativeUsd)
                ) {
                    effective.maxNativeUsd = current.rules.maxNativeUsd;
                }
                effective.canDelegate = effective.canDelegate && current.rules.canDelegate;
                effective.escalateNativeAmount = effective.escalateNativeAmount && current.rules.escalateNativeAmount;
                effective.escalateNativeUsd = effective.escalateNativeUsd && current.rules.escalateNativeUsd;
            }
            currentMandateId = current.parentMandateId;
        }
    }

    function _effectivePreflightRules(uint256 mandateId)
        private
        view
        returns (GrantlineTypes.PreflightRules memory effective)
    {
        uint256 currentMandateId = mandateId;
        bool initialized;
        while (currentMandateId != 0) {
            GrantlineTypes.Mandate storage current = _mandates[currentMandateId];
            if (!initialized) {
                effective = current.preflightRules;
                initialized = true;
            } else {
                if (current.preflightRules.minNativeBalance > effective.minNativeBalance) {
                    effective.minNativeBalance = current.preflightRules.minNativeBalance;
                }
                effective.escalateNativeBalance =
                    effective.escalateNativeBalance && current.preflightRules.escalateNativeBalance;
            }
            currentMandateId = current.parentMandateId;
        }
    }

    function _effectiveValidityWindow(uint256 mandateId) private view returns (uint64 validAfter, uint64 validUntil) {
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            GrantlineTypes.Mandate storage current = _mandates[currentMandateId];
            if (current.validAfter != 0 && current.validAfter > validAfter) {
                validAfter = current.validAfter;
            }
            if (current.validUntil != 0 && (validUntil == 0 || current.validUntil < validUntil)) {
                validUntil = current.validUntil;
            }
            currentMandateId = current.parentMandateId;
        }
    }

    function _isWithinValidityWindow(uint64 validAfter, uint64 validUntil) private view returns (bool) {
        return (validAfter == 0 || block.timestamp >= validAfter) && (validUntil == 0 || block.timestamp <= validUntil);
    }

    function _requireController(address vault, address actor) private view {
        if (!isRegisteredVault[vault]) revert VaultNotRegistered(vault);
        if (!IGrantlineContext(grantline).isController(vault, actor)) {
            revert NotController(0, actor);
        }
    }

    function _requireMandateAdministrator(uint256 mandateId, GrantlineTypes.Mandate storage mandate, address actor)
        private
        view
    {
        if (isRegisteredVault[mandate.vault] && IGrantlineContext(grantline).isController(mandate.vault, actor)) {
            return;
        }
        if (mandate.parentMandateId != 0) {
            GrantlineTypes.Mandate storage parent = _mandates[mandate.parentMandateId];
            if (parent.agent == actor) {
                _requireActiveLineage(mandate.parentMandateId);
                return;
            }
        }
        revert NotMandateAdministrator(mandateId, actor);
    }

    function _requireNonceCanceller(uint256 mandateId, GrantlineTypes.Mandate storage mandate, address actor)
        private
        view
    {
        if (mandate.agent == actor) return;
        if (isRegisteredVault[mandate.vault] && IGrantlineContext(grantline).isController(mandate.vault, actor)) {
            return;
        }
        revert NotNonceCanceller(mandateId, actor);
    }

    function _validateChildRules(
        uint256 parentMandateId,
        GrantlineTypes.MandateRules memory parentRules,
        GrantlineTypes.MandateRules memory childRules
    ) private pure {
        if (
            (parentRules.minNativeAmount != 0
                    && (childRules.minNativeAmount == 0 || childRules.minNativeAmount < parentRules.minNativeAmount))
                || (parentRules.maxNativeAmount != 0
                    && (childRules.maxNativeAmount == 0 || childRules.maxNativeAmount > parentRules.maxNativeAmount))
                || (parentRules.minNativeUsd != 0
                    && (childRules.minNativeUsd == 0 || childRules.minNativeUsd < parentRules.minNativeUsd))
                || (parentRules.maxNativeUsd != 0
                    && (childRules.maxNativeUsd == 0 || childRules.maxNativeUsd > parentRules.maxNativeUsd))
                || (childRules.canDelegate && !parentRules.canDelegate)
                || (childRules.escalateNativeAmount && !parentRules.escalateNativeAmount)
                || (childRules.escalateNativeUsd && !parentRules.escalateNativeUsd)
        ) revert ChildRulesExceedParent(parentMandateId);
    }

    function _validateChildPreflightRules(
        uint256 parentMandateId,
        GrantlineTypes.PreflightRules memory parentRules,
        GrantlineTypes.PreflightRules memory childRules
    ) private pure {
        if (
            (parentRules.minNativeBalance != 0
                    && (childRules.minNativeBalance == 0 || childRules.minNativeBalance < parentRules.minNativeBalance))
                || (childRules.escalateNativeBalance && !parentRules.escalateNativeBalance)
        ) revert ChildPreflightRulesExceedParent(parentMandateId);
    }

    function _requireMandateAgent(GrantlineTypes.Mandate storage mandate, uint256 mandateId, address agent)
        private
        view
    {
        if (mandate.agent != agent) {
            revert MandateAgentMismatch(mandateId, agent);
        }
    }

    function _requireNonceUnused(uint256 mandateId, address agent, uint256 nonce) private view {
        if (nonceUsed[mandateId][agent][nonce]) {
            revert NonceAlreadyUsed(mandateId, agent, nonce);
        }
    }

    function _validateRules(GrantlineTypes.MandateRules memory rules) private view {
        if (rules.minNativeAmount != 0 && rules.maxNativeAmount != 0 && rules.minNativeAmount > rules.maxNativeAmount) {
            revert InvalidNativeAmountRange(rules.minNativeAmount, rules.maxNativeAmount);
        }
        if (rules.minNativeUsd != 0 && rules.maxNativeUsd != 0 && rules.minNativeUsd > rules.maxNativeUsd) {
            revert InvalidNativeUsdRange(rules.minNativeUsd, rules.maxNativeUsd);
        }
        if (rules.minNativeUsd == 0 && rules.maxNativeUsd == 0) return;

        address evaluatorAddress = IGrantlineContext(grantline).moduleAddress(EVALUATOR_MODULE);
        if (evaluatorAddress == address(0) || !IEvaluator(evaluatorAddress).nativeUsdValuationEnabled()) {
            revert NativeUsdValuationUnsupported();
        }
        uint256 scale = 10 ** uint256(IEvaluator(evaluatorAddress).chainlinkNativeUsdFeedDecimals());
        if (rules.minNativeUsd > type(uint256).max / scale) {
            revert NativeUsdThresholdTooLarge(rules.minNativeUsd);
        }
        if (rules.maxNativeUsd > type(uint256).max / scale) {
            revert NativeUsdThresholdTooLarge(rules.maxNativeUsd);
        }
    }

    function _validatePreflightRules(GrantlineTypes.PreflightRules memory) private pure {}

    function _validateValidityWindow(uint64 validAfter, uint64 validUntil) private pure {
        if (validAfter != 0 && validUntil != 0 && validUntil < validAfter) {
            revert InvalidValidityWindow(validAfter, validUntil);
        }
    }

    function _onlyGrantline() private view {
        if (msg.sender != grantline) revert NotGrantline(msg.sender);
    }

    function _onlyExecutor() private view {
        if (msg.sender != IGrantlineContext(grantline).moduleAddress(EXECUTOR_MODULE)) revert NotExecutor(msg.sender);
    }

    function _onlyEscalationManager() private view {
        if (msg.sender != IGrantlineContext(grantline).moduleAddress(ESCALATION_MANAGER_MODULE)) {
            revert NotEscalationManager(msg.sender);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
