import type { Address, Hex } from "viem";

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
