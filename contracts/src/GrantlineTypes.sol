// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "./ActionTypes.sol";

library GrantlineTypes {
    enum MandateStatus {
        ACTIVE,
        PAUSED,
        REVOKED
    }

    struct MandateRules {
        bool canDelegate;
        uint256 minNativeAmount;
        uint256 maxNativeAmount;
        bool escalateNativeAmount;
        uint256 minNativeUsd;
        uint256 maxNativeUsd;
        bool escalateNativeUsd;
    }

    struct PreflightRules {
        uint256 minNativeBalance;
        bool escalateNativeBalance;
    }

    struct Mandate {
        uint256 id;
        address vault;
        address agent;
        uint256 parentMandateId;
        uint8 delegationDepth;
        MandateStatus status;
        MandateRules rules;
        PreflightRules preflightRules;
        uint64 validAfter;
        uint64 validUntil;
        uint64 createdAt;
        uint64 revokedAt;
    }

    struct MandateView {
        uint256 id;
        address controller;
        address vault;
        address agent;
        uint256 parentMandateId;
        uint8 delegationDepth;
        MandateStatus status;
        MandateRules rules;
        PreflightRules preflightRules;
        uint64 validAfter;
        uint64 validUntil;
        uint64 createdAt;
        uint64 revokedAt;
    }

    struct EvaluationResult {
        uint8 decision;
        uint8 failureCode;
        uint256 failedActionIndex;
        uint256 nativeAmount;
        uint256 nativeUsdValue;
        uint256 nativeBalanceAfter;
    }

    struct Escalation {
        ActionTypes.ActionPlan plan;
        bytes signature;
        address submittedBy;
        uint8 status;
        uint64 submittedAt;
    }
}
