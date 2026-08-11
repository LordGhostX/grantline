// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library ActionTypes {
    enum ActionType {
        TRANSFER
    }

    struct ActionPlan {
        uint256 mandateId;
        address agent;
        uint256 nonce;
        uint256 deadline;
        Action[] actions;
    }

    struct Action {
        ActionType actionType;
        uint8 version;
        bytes parameters;
    }

    struct TransferParameters {
        address asset;
        address recipient;
        uint256 amount;
    }
}
