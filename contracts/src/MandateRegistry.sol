// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IVaultOwner {
    function owner() external view returns (address);
}

interface IVaultAuthority {
    function authority() external view returns (address);
}

contract MandateRegistry {
    enum MandateStatus {
        ACTIVE,
        REVOKED
    }

    struct Mandate {
        uint256 id;
        address owner;
        address vault;
        address agent;
        MandateStatus status;
        uint256 transactionLimit;
        uint256 usdTransactionLimit;
        uint64 createdAt;
        uint64 revokedAt;
    }

    error InvalidAddress();
    error InvalidVault();
    error MandateNotActive(uint256 mandateId);
    error MandateNotFound(uint256 mandateId);
    error MandateAgentMismatch(uint256 mandateId, address agent);
    error NonceAlreadyUsed(uint256 mandateId, address agent, uint256 nonce);
    error NotVaultAuthority(address caller);
    error NotVaultOwner(address caller);

    event MandateCreated(
        uint256 indexed mandateId,
        address indexed owner,
        address indexed vault,
        address agent,
        uint256 transactionLimit,
        uint256 usdTransactionLimit,
        uint64 createdAt
    );
    event MandateUpdated(
        uint256 indexed mandateId,
        uint256 transactionLimit,
        uint256 usdTransactionLimit,
        uint64 updatedAt
    );
    event MandateRevoked(
        uint256 indexed mandateId,
        address indexed owner,
        uint64 revokedAt
    );

    mapping(uint256 mandateId => Mandate mandate) private _mandates;
    mapping(uint256 mandateId => mapping(address agent => mapping(uint256 nonce => bool)))
        public nonceUsed;
    uint256 public mandateCount;

    function createMandate(
        address vault,
        address agent,
        uint256 transactionLimit,
        uint256 usdTransactionLimit
    ) external returns (uint256 mandateId) {
        _requireValidAddresses(vault, agent);
        _requireVaultOwner(vault, msg.sender);

        mandateId = ++mandateCount;
        uint64 createdAt = uint64(block.timestamp);
        _mandates[mandateId] = Mandate({
            id: mandateId,
            owner: msg.sender,
            vault: vault,
            agent: agent,
            status: MandateStatus.ACTIVE,
            transactionLimit: transactionLimit,
            usdTransactionLimit: usdTransactionLimit,
            createdAt: createdAt,
            revokedAt: 0
        });

        emit MandateCreated(
            mandateId,
            msg.sender,
            vault,
            agent,
            transactionLimit,
            usdTransactionLimit,
            createdAt
        );
    }

    function updateMandate(
        uint256 mandateId,
        uint256 transactionLimit,
        uint256 usdTransactionLimit
    ) external {
        Mandate storage mandate = _activeMandate(mandateId);
        _requireVaultOwner(mandate.vault, msg.sender);

        mandate.transactionLimit = transactionLimit;
        mandate.usdTransactionLimit = usdTransactionLimit;

        emit MandateUpdated(
            mandateId,
            transactionLimit,
            usdTransactionLimit,
            uint64(block.timestamp)
        );
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
        if (mandate.agent != agent) {
            revert MandateAgentMismatch(mandateId, agent);
        }
        _requireVaultAuthority(mandate.vault, msg.sender);

        if (nonceUsed[mandateId][agent][nonce]) {
            revert NonceAlreadyUsed(mandateId, agent, nonce);
        }
        nonceUsed[mandateId][agent][nonce] = true;
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

    function _requireValidAddresses(address vault, address agent) private pure {
        if (vault == address(0) || agent == address(0)) revert InvalidAddress();
    }
}
