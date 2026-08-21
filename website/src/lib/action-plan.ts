import {
  decodeAbiParameters,
  hashTypedData,
  type Address,
  type Hex,
} from "viem";
import { addresses, chainId } from "./contracts";

export const actionPlanDomain = {
  name: "Grantline",
  version: "1",
  chainId,
  verifyingContract: addresses.grantline,
} as const;

export const actionTypes = {
  Action: [
    { name: "actionType", type: "uint8" },
    { name: "version", type: "uint8" },
    { name: "parameters", type: "bytes" },
  ],
  ActionPlan: [
    { name: "mandateId", type: "uint256" },
    { name: "agent", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "actions", type: "Action[]" },
  ],
} as const;

export const demoAgentAuthorizationDomain = {
  name: "Grantline Demo Agent Authorization",
  version: "1",
  chainId,
  verifyingContract: addresses.grantline,
} as const;

export const demoAgentAuthorizationTypes = {
  DemoAgentAuthorization: [
    { name: "mandateId", type: "uint256" },
    { name: "agent", type: "address" },
    { name: "actionDigest", type: "bytes32" },
    { name: "expiresAt", type: "uint256" },
  ],
} as const;

export const demoAgentAuthorizationTtlSeconds = 5 * 60;
export const demoAgentAuthorizationMaxTtlSeconds = 10 * 60;

export type ActionPlanAction = {
  actionType: number;
  version: number;
  parameters: Hex;
};

export type DecodedAction =
  | {
      kind: "transfer";
      asset: Address;
      recipient: Address;
      amount: bigint;
    }
  | {
      kind: "swap";
      adapterId: number;
      tokenIn: Address;
      amountIn: bigint;
      tokenOut: Address;
      minAmountOut: bigint;
      hops: readonly {
        pool: Address;
        tokenIn: Address;
        tokenOut: Address;
      }[];
    }
  | {
      kind: "unknown";
      actionType: number;
      version: number;
      parameters: Hex;
    };

const transferParameters = [
  {
    type: "tuple",
    components: [
      { name: "asset", type: "address" },
      { name: "recipient", type: "address" },
      { name: "amount", type: "uint256" },
    ],
  },
] as const;

const swapParameters = [
  {
    type: "tuple",
    components: [
      { name: "swapAdapterId", type: "uint8" },
      { name: "tokenIn", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "tokenOut", type: "address" },
      { name: "minAmountOut", type: "uint256" },
      {
        name: "hops",
        type: "tuple[]",
        components: [
          { name: "pool", type: "address" },
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
        ],
      },
    ],
  },
] as const;

export function decodeAction(action: ActionPlanAction): DecodedAction {
  try {
    if (action.actionType === 0) {
      const [transfer] = decodeAbiParameters(
        transferParameters,
        action.parameters,
      );
      return {
        kind: "transfer",
        asset: transfer.asset,
        recipient: transfer.recipient,
        amount: transfer.amount,
      };
    }

    if (action.actionType === 1) {
      const [swap] = decodeAbiParameters(swapParameters, action.parameters);
      return {
        kind: "swap",
        adapterId: swap.swapAdapterId,
        tokenIn: swap.tokenIn,
        amountIn: swap.amountIn,
        tokenOut: swap.tokenOut,
        minAmountOut: swap.minAmountOut,
        hops: swap.hops.map((hop) => ({
          pool: hop.pool,
          tokenIn: hop.tokenIn,
          tokenOut: hop.tokenOut,
        })),
      };
    }
  } catch {
    // Preserve the action metadata when a future or malformed payload cannot
    // be decoded, so the reviewer still knows what was submitted.
  }

  return {
    kind: "unknown",
    actionType: action.actionType,
    version: action.version,
    parameters: action.parameters,
  };
}

export type ActionPlan = {
  mandateId: bigint;
  agent: Address;
  nonce: bigint;
  deadline: bigint;
  actions: readonly ActionPlanAction[];
};

export type DemoAgentAuthorization = {
  mandateId: bigint;
  agent: Address;
  actionDigest: Hex;
  expiresAt: bigint;
};

export type SerializedActionPlan = {
  mandateId: string;
  agent: Address;
  nonce: string;
  deadline: string;
  actions: readonly ActionPlanAction[];
};

export function serializeActionPlan(plan: ActionPlan): SerializedActionPlan {
  return {
    mandateId: plan.mandateId.toString(),
    agent: plan.agent,
    nonce: plan.nonce.toString(),
    deadline: plan.deadline.toString(),
    actions: plan.actions,
  };
}

export function hashActionPlan(plan: ActionPlan): Hex {
  return hashTypedData({
    domain: actionPlanDomain,
    types: actionTypes,
    primaryType: "ActionPlan",
    message: plan,
  });
}
