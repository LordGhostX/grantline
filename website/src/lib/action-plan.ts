import { hashTypedData, type Address, type Hex } from "viem";
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
