"use client";

import { isHex, type Hex } from "viem";
import {
  serializeActionPlan,
  type ActionPlan,
  type DemoAgentAuthorization,
} from "./action-plan";

type DemoAgentSignatureResponse = {
  signature?: unknown;
  error?: unknown;
};

export async function requestDemoAgentSignature(
  plan: ActionPlan,
  authorization: DemoAgentAuthorization & { signature: Hex },
): Promise<Hex> {
  const response = await fetch("/api/demo-agent/sign", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      plan: serializeActionPlan(plan),
      controllerAuthorization: {
        actionDigest: authorization.actionDigest,
        expiresAt: authorization.expiresAt.toString(),
        signature: authorization.signature,
      },
    }),
  });

  let payload: DemoAgentSignatureResponse = {};
  try {
    payload = (await response.json()) as DemoAgentSignatureResponse;
  } catch {
    throw new Error(
      "The demo agent signing service returned an invalid response.",
    );
  }

  if (!response.ok) {
    throw new Error(
      typeof payload.error === "string"
        ? payload.error
        : "The demo agent could not sign this Action Plan.",
    );
  }

  if (typeof payload.signature !== "string" || !isHex(payload.signature)) {
    throw new Error(
      "The demo agent signing service returned an invalid signature.",
    );
  }

  return payload.signature;
}
