// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library ActionTypes {
    uint8 internal constant TRANSFER_VERSION = 1;
    uint8 internal constant SWAP_VERSION = 1;

    enum ActionType {
        TRANSFER,
        SWAP
    }

    enum SwapAdapterId {
        NONE,
        UNISWAP_V3
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

    struct SwapAdapterConfig {
        SwapAdapterId swapAdapterId;
        address swapAdapter;
    }

    struct SwapParameters {
        SwapAdapterId swapAdapterId;
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        SwapHop[] hops;
    }

    struct SwapHop {
        address pool;
        address tokenIn;
        address tokenOut;
    }
}
