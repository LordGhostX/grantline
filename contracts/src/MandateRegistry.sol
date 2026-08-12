// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IVaultOwner {
    function owner() external view returns (address);
}

interface IVaultAuthority {
    function authority() external view returns (address);
}

interface IVaultEscalationAuthority {
    function escalationManager() external view returns (address);
}

contract MandateRegistry {
    uint8 public constant MAX_DELEGATION_DEPTH = 2;

    enum MandateStatus {
        ACTIVE,
        REVOKED
    }

    struct MandateRules {
        bool canDelegate;
        uint256 minNativeAmount;
        uint256 maxNativeAmount;
        bool escalateNativeAmount;
        uint256 minUsdAmount;
        uint256 maxUsdAmount;
        bool escalateUsdAmount;
    }

    struct PreflightRules {
        uint256 minNativeBalance;
        bool escalateNativeBalance;
    }

    struct Mandate {
        uint256 id;
        address owner;
        address vault;
        address agent;
        uint256 parentMandateId;
        uint8 delegationDepth;
        MandateStatus status;
        MandateRules rules;
        PreflightRules preflightRules;
        uint64 createdAt;
        uint64 revokedAt;
    }

    error InvalidAddress();
    error InvalidVault();
    error MandateNotActive(uint256 mandateId);
    error MandateNotFound(uint256 mandateId);
    error MandateAgentMismatch(uint256 mandateId, address agent);
    error InvalidReservationDigest();
    error NonceAlreadyUsed(uint256 mandateId, address agent, uint256 nonce);
    error NonceReserved(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        bytes32 digest
    );
    error NonceReservationMismatch(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        bytes32 expectedDigest,
        bytes32 reservedDigest
    );
    error InvalidNativeAmountRange(uint256 minimum, uint256 maximum);
    error InvalidUsdAmountRange(uint256 minimum, uint256 maximum);
    error NotVaultAuthority(address caller);
    error NotVaultEscalationManager(address caller);
    error NotVaultOwner(address caller);
    error InvalidVaultAuthority(address authority);
    error MandateNotDelegatable(uint256 mandateId);
    error DelegationDepthExceeded(uint256 parentMandateId, uint8 depth);
    error InvalidDelegationAgent(address parentAgent, address childAgent);
    error NotParentAgent(uint256 mandateId, address caller);
    error NotMandateAdministrator(uint256 mandateId, address caller);
    error MandateLineageInactive(uint256 mandateId, uint256 inactiveAncestorId);
    error ChildRulesExceedParent(uint256 parentMandateId);
    error ChildPreflightRulesExceedParent(uint256 parentMandateId);

    event MandateCreated(
        uint256 indexed mandateId,
        address indexed owner,
        address indexed vault,
        address agent,
        uint256 parentMandateId,
        uint8 delegationDepth,
        MandateRules rules,
        PreflightRules preflightRules,
        address createdBy,
        uint64 createdAt
    );
    event MandateUpdated(
        uint256 indexed mandateId,
        MandateRules rules,
        PreflightRules preflightRules,
        address indexed updatedBy,
        uint64 updatedAt
    );
    event MandateRevoked(
        uint256 indexed mandateId,
        address indexed revokedBy,
        uint64 revokedAt
    );
    event NonceReservationCreated(
        uint256 indexed mandateId,
        address indexed agent,
        uint256 indexed nonce,
        bytes32 digest
    );
    event NonceReservationConsumed(
        uint256 indexed mandateId,
        address indexed agent,
        uint256 indexed nonce,
        bytes32 digest
    );

    mapping(uint256 mandateId => Mandate mandate) private _mandates;
    mapping(uint256 mandateId => mapping(address agent => mapping(uint256 nonce => bool)))
        public nonceUsed;
    mapping(uint256 mandateId => mapping(address agent => mapping(uint256 nonce => bytes32 digest)))
        public reservedDigest;
    uint256 public mandateCount;

    function createMandate(
        address vault,
        address agent,
        MandateRules calldata rules,
        PreflightRules calldata preflightRules
    ) external returns (uint256 mandateId) {
        mandateId = _createMandate(vault, agent, rules, preflightRules);
    }

    function _createMandate(
        address vault,
        address agent,
        MandateRules memory rules,
        PreflightRules memory preflightRules
    ) private returns (uint256 mandateId) {
        _requireValidAddresses(vault, agent);
        _requireVaultOwner(vault, msg.sender);
        _validateRules(rules);
        _validatePreflightRules(preflightRules);

        mandateId = ++mandateCount;
        uint64 createdAt = uint64(block.timestamp);
        _mandates[mandateId] = Mandate({
            id: mandateId,
            owner: msg.sender,
            vault: vault,
            agent: agent,
            parentMandateId: 0,
            delegationDepth: 0,
            status: MandateStatus.ACTIVE,
            rules: rules,
            preflightRules: preflightRules,
            createdAt: createdAt,
            revokedAt: 0
        });

        emit MandateCreated(
            mandateId,
            msg.sender,
            vault,
            agent,
            0,
            0,
            rules,
            preflightRules,
            msg.sender,
            createdAt
        );
    }

    function createChildMandate(
        uint256 parentMandateId,
        address childAgent,
        MandateRules calldata rules,
        PreflightRules calldata preflightRules
    ) external returns (uint256 mandateId) {
        Mandate storage parent = _activeMandate(parentMandateId);
        if (parent.agent != msg.sender) {
            revert NotParentAgent(parentMandateId, msg.sender);
        }

        _requireActiveLineage(parentMandateId);
        MandateRules memory parentRules = _effectiveRules(parentMandateId);
        PreflightRules memory parentPreflightRules = _effectivePreflightRules(
            parentMandateId
        );
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
        _validateChildRules(parentMandateId, parentRules, rules);
        _validateChildPreflightRules(
            parentMandateId,
            parentPreflightRules,
            preflightRules
        );
        address vaultOwner = _vaultOwner(parent.vault);

        mandateId = ++mandateCount;
        uint64 createdAt = uint64(block.timestamp);
        _mandates[mandateId] = Mandate({
            id: mandateId,
            owner: vaultOwner,
            vault: parent.vault,
            agent: childAgent,
            parentMandateId: parentMandateId,
            delegationDepth: childDepth,
            status: MandateStatus.ACTIVE,
            rules: rules,
            preflightRules: preflightRules,
            createdAt: createdAt,
            revokedAt: 0
        });

        emit MandateCreated(
            mandateId,
            vaultOwner,
            parent.vault,
            childAgent,
            parentMandateId,
            childDepth,
            rules,
            preflightRules,
            msg.sender,
            createdAt
        );
    }

    function updateMandate(
        uint256 mandateId,
        MandateRules calldata rules,
        PreflightRules calldata preflightRules
    ) external {
        _updateMandate(mandateId, rules, preflightRules);
    }

    function _updateMandate(
        uint256 mandateId,
        MandateRules memory rules,
        PreflightRules memory preflightRules
    ) private {
        Mandate storage mandate = _activeMandate(mandateId);
        _requireMandateAdministrator(mandateId, mandate);
        if (mandate.delegationDepth == MAX_DELEGATION_DEPTH) {
            rules.canDelegate = false;
        }
        _validateRules(rules);
        _validatePreflightRules(preflightRules);
        if (mandate.parentMandateId != 0) {
            _requireActiveLineage(mandate.parentMandateId);
            _validateChildRules(
                mandate.parentMandateId,
                _effectiveRules(mandate.parentMandateId),
                rules
            );
            _validateChildPreflightRules(
                mandate.parentMandateId,
                _effectivePreflightRules(mandate.parentMandateId),
                preflightRules
            );
        }

        mandate.rules = rules;
        mandate.preflightRules = preflightRules;

        emit MandateUpdated(
            mandateId,
            rules,
            preflightRules,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    function revokeMandate(uint256 mandateId) external {
        Mandate storage mandate = _activeMandate(mandateId);
        _requireMandateAdministrator(mandateId, mandate);

        uint64 revokedAt = uint64(block.timestamp);
        mandate.status = MandateStatus.REVOKED;
        mandate.revokedAt = revokedAt;

        emit MandateRevoked(mandateId, msg.sender, revokedAt);
    }

    function consumeNonce(
        uint256 mandateId,
        address agent,
        uint256 nonce
    ) external {
        Mandate storage mandate = _activeMandate(mandateId);
        _requireActiveLineage(mandateId);
        _requireMandateAgent(mandate, mandateId, agent);
        _requireVaultAuthority(mandate.vault, msg.sender);
        _requireNonceUnused(mandateId, agent, nonce);

        bytes32 reservation = reservedDigest[mandateId][agent][nonce];
        if (reservation != bytes32(0)) {
            revert NonceReserved(mandateId, agent, nonce, reservation);
        }
        nonceUsed[mandateId][agent][nonce] = true;
    }

    function reserveNonce(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        bytes32 actionDigest
    ) external {
        if (actionDigest == bytes32(0)) revert InvalidReservationDigest();

        Mandate storage mandate = _activeMandate(mandateId);
        _requireActiveLineage(mandateId);
        _requireMandateAgent(mandate, mandateId, agent);
        _requireVaultEscalationManager(mandate.vault, msg.sender);
        _requireNonceUnused(mandateId, agent, nonce);

        bytes32 existingDigest = reservedDigest[mandateId][agent][nonce];
        if (existingDigest != bytes32(0)) {
            revert NonceReserved(mandateId, agent, nonce, existingDigest);
        }
        reservedDigest[mandateId][agent][nonce] = actionDigest;
        emit NonceReservationCreated(mandateId, agent, nonce, actionDigest);
    }

    function consumeReservedNonce(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        bytes32 actionDigest
    ) external {
        if (actionDigest == bytes32(0)) revert InvalidReservationDigest();

        Mandate storage mandate = _activeMandate(mandateId);
        _requireActiveLineage(mandateId);
        _requireMandateAgent(mandate, mandateId, agent);
        _requireVaultAuthority(mandate.vault, msg.sender);
        _requireNonceUnused(mandateId, agent, nonce);

        bytes32 reservation = reservedDigest[mandateId][agent][nonce];
        if (reservation != actionDigest) {
            revert NonceReservationMismatch(
                mandateId,
                agent,
                nonce,
                actionDigest,
                reservation
            );
        }

        delete reservedDigest[mandateId][agent][nonce];
        nonceUsed[mandateId][agent][nonce] = true;
        emit NonceReservationConsumed(mandateId, agent, nonce, actionDigest);
    }

    function getMandate(
        uint256 mandateId
    ) external view returns (Mandate memory) {
        if (mandateId == 0 || mandateId > mandateCount) {
            revert MandateNotFound(mandateId);
        }
        return _mandates[mandateId];
    }

    function getLineage(
        uint256 mandateId
    ) external view returns (uint256[] memory lineage) {
        _requireMandateExists(mandateId);
        uint256 length = uint256(_mandates[mandateId].delegationDepth) + 1;
        lineage = new uint256[](length);
        uint256 currentMandateId = mandateId;
        for (uint256 index = length; index > 0; index--) {
            lineage[index - 1] = currentMandateId;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
    }

    function getEffectiveRules(
        uint256 mandateId
    ) external view returns (MandateRules memory) {
        _requireActiveLineage(mandateId);
        return _effectiveRules(mandateId);
    }

    function getEffectivePreflightRules(
        uint256 mandateId
    ) external view returns (PreflightRules memory) {
        _requireActiveLineage(mandateId);
        return _effectivePreflightRules(mandateId);
    }

    function isActive(uint256 mandateId) external view returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        return _mandates[mandateId].status == MandateStatus.ACTIVE;
    }

    function isLineageActive(uint256 mandateId) external view returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            if (_mandates[currentMandateId].status != MandateStatus.ACTIVE) {
                return false;
            }
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
        return true;
    }

    function _activeMandate(
        uint256 mandateId
    ) private view returns (Mandate storage mandate) {
        if (mandateId == 0 || mandateId > mandateCount) {
            revert MandateNotFound(mandateId);
        }

        mandate = _mandates[mandateId];
        if (mandate.status != MandateStatus.ACTIVE) {
            revert MandateNotActive(mandateId);
        }
    }

    function _requireMandateExists(
        uint256 mandateId
    ) private view returns (Mandate storage mandate) {
        if (mandateId == 0 || mandateId > mandateCount) {
            revert MandateNotFound(mandateId);
        }
        return _mandates[mandateId];
    }

    function _requireActiveLineage(uint256 mandateId) private view {
        _requireMandateExists(mandateId);
        uint256 currentMandateId = mandateId;
        while (currentMandateId != 0) {
            Mandate storage current = _mandates[currentMandateId];
            if (current.status != MandateStatus.ACTIVE) {
                revert MandateLineageInactive(mandateId, currentMandateId);
            }
            currentMandateId = current.parentMandateId;
        }
    }

    function _effectiveRules(
        uint256 mandateId
    ) private view returns (MandateRules memory effective) {
        effective = _mandates[mandateId].rules;
        uint256 currentMandateId = _mandates[mandateId].parentMandateId;
        while (currentMandateId != 0) {
            MandateRules storage parentRules = _mandates[currentMandateId]
                .rules;
            if (parentRules.minNativeAmount > effective.minNativeAmount) {
                effective.minNativeAmount = parentRules.minNativeAmount;
            }
            if (
                parentRules.maxNativeAmount != 0 &&
                (effective.maxNativeAmount == 0 ||
                    parentRules.maxNativeAmount < effective.maxNativeAmount)
            ) {
                effective.maxNativeAmount = parentRules.maxNativeAmount;
            }
            if (parentRules.minUsdAmount > effective.minUsdAmount) {
                effective.minUsdAmount = parentRules.minUsdAmount;
            }
            if (
                parentRules.maxUsdAmount != 0 &&
                (effective.maxUsdAmount == 0 ||
                    parentRules.maxUsdAmount < effective.maxUsdAmount)
            ) {
                effective.maxUsdAmount = parentRules.maxUsdAmount;
            }
            effective.escalateNativeAmount =
                effective.escalateNativeAmount &&
                parentRules.escalateNativeAmount;
            effective.escalateUsdAmount =
                effective.escalateUsdAmount &&
                parentRules.escalateUsdAmount;
            effective.canDelegate =
                effective.canDelegate &&
                parentRules.canDelegate;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
    }

    function _effectivePreflightRules(
        uint256 mandateId
    ) private view returns (PreflightRules memory effective) {
        effective = _mandates[mandateId].preflightRules;
        uint256 currentMandateId = _mandates[mandateId].parentMandateId;
        while (currentMandateId != 0) {
            PreflightRules storage parentRules = _mandates[currentMandateId]
                .preflightRules;
            if (parentRules.minNativeBalance > effective.minNativeBalance) {
                effective.minNativeBalance = parentRules.minNativeBalance;
            }
            effective.escalateNativeBalance =
                effective.escalateNativeBalance &&
                parentRules.escalateNativeBalance;
            currentMandateId = _mandates[currentMandateId].parentMandateId;
        }
    }

    function _validateChildRules(
        uint256 parentMandateId,
        MandateRules memory parentRules,
        MandateRules memory childRules
    ) private pure {
        if (
            (parentRules.minNativeAmount != 0 &&
                (childRules.minNativeAmount == 0 ||
                    childRules.minNativeAmount <
                    parentRules.minNativeAmount)) ||
            (parentRules.maxNativeAmount != 0 &&
                (childRules.maxNativeAmount == 0 ||
                    childRules.maxNativeAmount >
                    parentRules.maxNativeAmount)) ||
            (parentRules.minUsdAmount != 0 &&
                (childRules.minUsdAmount == 0 ||
                    childRules.minUsdAmount < parentRules.minUsdAmount)) ||
            (parentRules.maxUsdAmount != 0 &&
                (childRules.maxUsdAmount == 0 ||
                    childRules.maxUsdAmount > parentRules.maxUsdAmount)) ||
            (childRules.escalateNativeAmount &&
                !parentRules.escalateNativeAmount) ||
            (childRules.escalateUsdAmount && !parentRules.escalateUsdAmount) ||
            (childRules.canDelegate && !parentRules.canDelegate)
        ) {
            revert ChildRulesExceedParent(parentMandateId);
        }
    }

    function _validateChildPreflightRules(
        uint256 parentMandateId,
        PreflightRules memory parentRules,
        PreflightRules memory childRules
    ) private pure {
        if (
            (parentRules.minNativeBalance != 0 &&
                (childRules.minNativeBalance == 0 ||
                    childRules.minNativeBalance <
                    parentRules.minNativeBalance)) ||
            (childRules.escalateNativeBalance &&
                !parentRules.escalateNativeBalance)
        ) {
            revert ChildPreflightRulesExceedParent(parentMandateId);
        }
    }

    function _requireMandateAdministrator(
        uint256 mandateId,
        Mandate storage mandate
    ) private view {
        if (_isVaultOwner(mandate.vault, msg.sender)) return;
        if (mandate.parentMandateId != 0) {
            Mandate storage parent = _mandates[mandate.parentMandateId];
            if (parent.agent == msg.sender) {
                _requireActiveLineage(mandate.parentMandateId);
                return;
            }
        }
        revert NotMandateAdministrator(mandateId, msg.sender);
    }

    function _isVaultOwner(
        address vault,
        address caller
    ) private view returns (bool) {
        if (vault.code.length == 0) revert InvalidVault();
        try IVaultOwner(vault).owner() returns (address vaultOwner) {
            return vaultOwner == caller;
        } catch {
            revert InvalidVault();
        }
    }

    function _vaultOwner(address vault) private view returns (address owner) {
        if (vault.code.length == 0) revert InvalidVault();
        try IVaultOwner(vault).owner() returns (address vaultOwner) {
            return vaultOwner;
        } catch {
            revert InvalidVault();
        }
    }

    function _requireVaultOwner(address vault, address caller) private view {
        if (vault.code.length == 0) revert InvalidVault();

        try IVaultOwner(vault).owner() returns (address vaultOwner) {
            if (vaultOwner != caller) revert NotVaultOwner(caller);
        } catch {
            revert InvalidVault();
        }
    }

    function _requireVaultAuthority(
        address vault,
        address caller
    ) private view {
        if (vault.code.length == 0) revert InvalidVault();

        try IVaultAuthority(vault).authority() returns (
            address vaultAuthority
        ) {
            if (vaultAuthority != caller) revert NotVaultAuthority(caller);
        } catch {
            revert InvalidVault();
        }
    }

    function _requireVaultEscalationManager(
        address vault,
        address caller
    ) private view {
        if (vault.code.length == 0) revert InvalidVault();

        address vaultAuthority;
        try IVaultAuthority(vault).authority() returns (address authority) {
            vaultAuthority = authority;
        } catch {
            revert InvalidVault();
        }
        if (vaultAuthority.code.length == 0) {
            revert InvalidVaultAuthority(vaultAuthority);
        }

        try
            IVaultEscalationAuthority(vaultAuthority).escalationManager()
        returns (address manager) {
            if (manager != caller) revert NotVaultEscalationManager(caller);
        } catch {
            revert InvalidVaultAuthority(vaultAuthority);
        }
    }

    function _requireMandateAgent(
        Mandate storage mandate,
        uint256 mandateId,
        address agent
    ) private view {
        if (mandate.agent != agent) {
            revert MandateAgentMismatch(mandateId, agent);
        }
    }

    function _requireNonceUnused(
        uint256 mandateId,
        address agent,
        uint256 nonce
    ) private view {
        if (nonceUsed[mandateId][agent][nonce]) {
            revert NonceAlreadyUsed(mandateId, agent, nonce);
        }
    }

    function _requireValidAddresses(address vault, address agent) private pure {
        if (vault == address(0) || agent == address(0)) revert InvalidAddress();
    }

    function _validateRules(MandateRules memory rules) private pure {
        if (
            rules.minNativeAmount != 0 &&
            rules.maxNativeAmount != 0 &&
            rules.minNativeAmount > rules.maxNativeAmount
        ) {
            revert InvalidNativeAmountRange(
                rules.minNativeAmount,
                rules.maxNativeAmount
            );
        }
        if (
            rules.minUsdAmount != 0 &&
            rules.maxUsdAmount != 0 &&
            rules.minUsdAmount > rules.maxUsdAmount
        ) {
            revert InvalidUsdAmountRange(
                rules.minUsdAmount,
                rules.maxUsdAmount
            );
        }
    }

    function _validatePreflightRules(PreflightRules memory) private pure {}
}
