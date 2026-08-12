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
    enum MandateStatus {
        ACTIVE,
        REVOKED
    }

    struct MandateRules {
        uint256 minNativeAmount;
        uint256 maxNativeAmount;
        bool escalateNativeAmount;
        uint256 minUsdAmount;
        uint256 maxUsdAmount;
        bool escalateUsdAmount;
    }

    struct Mandate {
        uint256 id;
        address owner;
        address vault;
        address agent;
        MandateStatus status;
        MandateRules rules;
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

    event MandateCreated(
        uint256 indexed mandateId,
        address indexed owner,
        address indexed vault,
        address agent,
        MandateRules rules,
        uint64 createdAt
    );
    event MandateUpdated(
        uint256 indexed mandateId,
        MandateRules rules,
        uint64 updatedAt
    );
    event MandateRevoked(
        uint256 indexed mandateId,
        address indexed owner,
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
        MandateRules calldata rules
    ) external returns (uint256 mandateId) {
        mandateId = _createMandate(vault, agent, rules);
    }

    function _createMandate(
        address vault,
        address agent,
        MandateRules memory rules
    ) private returns (uint256 mandateId) {
        _requireValidAddresses(vault, agent);
        _requireVaultOwner(vault, msg.sender);
        _validateRules(rules);

        mandateId = ++mandateCount;
        uint64 createdAt = uint64(block.timestamp);
        _mandates[mandateId] = Mandate({
            id: mandateId,
            owner: msg.sender,
            vault: vault,
            agent: agent,
            status: MandateStatus.ACTIVE,
            rules: rules,
            createdAt: createdAt,
            revokedAt: 0
        });

        emit MandateCreated(
            mandateId,
            msg.sender,
            vault,
            agent,
            rules,
            createdAt
        );
    }

    function updateMandate(
        uint256 mandateId,
        MandateRules calldata rules
    ) external {
        _updateMandate(mandateId, rules);
    }

    function _updateMandate(
        uint256 mandateId,
        MandateRules memory rules
    ) private {
        Mandate storage mandate = _activeMandate(mandateId);
        _requireVaultOwner(mandate.vault, msg.sender);
        _validateRules(rules);

        mandate.rules = rules;

        emit MandateUpdated(mandateId, rules, uint64(block.timestamp));
    }

    function revokeMandate(uint256 mandateId) external {
        Mandate storage mandate = _activeMandate(mandateId);
        _requireVaultOwner(mandate.vault, msg.sender);

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

    function isActive(uint256 mandateId) external view returns (bool) {
        if (mandateId == 0 || mandateId > mandateCount) return false;
        return _mandates[mandateId].status == MandateStatus.ACTIVE;
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
}
