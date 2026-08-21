import { NextResponse } from "next/server";
import {
  createPublicClient,
  fallback,
  getAddress,
  http,
  isAddress,
  isHex,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  actionPlanDomain,
  actionTypes,
  demoAgentAuthorizationDomain,
  demoAgentAuthorizationMaxTtlSeconds,
  demoAgentAuthorizationTypes,
  hashActionPlan,
  type ActionPlan,
} from "@/lib/action-plan";
import { addresses, chainId, demoAgent, grantlineAbi } from "@/lib/contracts";

export const runtime = "nodejs";

const UINT256_MAX = (1n << 256n) - 1n;

function errorResponse(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function parseUint(value: unknown, field: string): bigint {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${field} must be a decimal whole number.`);
  }

  const parsed = BigInt(value);
  if (parsed > UINT256_MAX) {
    throw new Error(`${field} exceeds the uint256 range.`);
  }

  return parsed;
}

function parsePlan(value: unknown): ActionPlan {
  if (!isRecord(value)) {
    throw new Error("The request must contain an Action Plan.");
  }

  if (typeof value.agent !== "string" || !isAddress(value.agent)) {
    throw new Error("Action Plan agent must be a valid Ethereum address.");
  }

  if (!Array.isArray(value.actions) || value.actions.length === 0) {
    throw new Error("Action Plan must contain at least one action.");
  }

  const actions = value.actions.map((action, index) => {
    if (!isRecord(action)) {
      throw new Error(`Action ${index + 1} is invalid.`);
    }

    const { actionType, version, parameters } = action;
    if (
      typeof actionType !== "number" ||
      !Number.isInteger(actionType) ||
      actionType < 0 ||
      actionType > 255
    ) {
      throw new Error(`Action ${index + 1} has an invalid action type.`);
    }
    if (
      typeof version !== "number" ||
      !Number.isInteger(version) ||
      version < 0 ||
      version > 255
    ) {
      throw new Error(`Action ${index + 1} has an invalid version.`);
    }
    if (typeof parameters !== "string" || !isHex(parameters)) {
      throw new Error(`Action ${index + 1} parameters must be hex data.`);
    }

    return { actionType, version, parameters };
  });

  return {
    mandateId: parseUint(value.mandateId, "mandateId"),
    agent: getAddress(value.agent),
    nonce: parseUint(value.nonce, "nonce"),
    deadline: parseUint(value.deadline, "deadline"),
    actions,
  };
}

type ControllerAuthorization = {
  actionDigest: Hex;
  expiresAt: bigint;
  signature: Hex;
};

function parseControllerAuthorization(value: unknown): ControllerAuthorization {
  if (!isRecord(value)) {
    throw new Error("The request must contain controller authorization.");
  }

  if (
    typeof value.actionDigest !== "string" ||
    !isHex(value.actionDigest) ||
    value.actionDigest.length !== 66
  ) {
    throw new Error("Controller authorization digest must be a bytes32 value.");
  }

  if (
    typeof value.signature !== "string" ||
    !isHex(value.signature) ||
    ![130, 132].includes(value.signature.length)
  ) {
    throw new Error("Controller authorization signature is invalid.");
  }

  return {
    actionDigest: value.actionDigest,
    expiresAt: parseUint(value.expiresAt, "authorization expiry"),
    signature: value.signature,
  };
}

function getPublicClient() {
  const rpcUrls = process.env.NEXT_PUBLIC_X_LAYER_RPCS?.split(",")
    .map((url) => url.trim())
    .filter(Boolean);
  if (!rpcUrls || rpcUrls.length === 0) {
    throw new Error("NEXT_PUBLIC_X_LAYER_RPCS is not configured.");
  }

  const transports = rpcUrls.map((url) => http(url));
  const xLayerTestnet = {
    id: chainId,
    name: "X Layer Testnet",
    nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
    rpcUrls: { default: { http: rpcUrls } },
  } as const;

  return createPublicClient({
    chain: xLayerTestnet,
    transport: transports.length === 1 ? transports[0] : fallback(transports),
  });
}

function readMandate(
  publicClient: ReturnType<typeof getPublicClient>,
  mandateId: bigint,
) {
  return publicClient.readContract({
    address: addresses.grantline,
    abi: grantlineAbi,
    functionName: "getMandate",
    args: [mandateId],
  });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse("Request body must be valid JSON.", 400);
  }

  if (
    !isRecord(body) ||
    !("plan" in body) ||
    !("controllerAuthorization" in body)
  ) {
    return errorResponse(
      "Request must contain a plan and controller authorization.",
      400,
    );
  }

  let plan: ActionPlan;
  try {
    plan = parsePlan(body.plan);
  } catch (error) {
    return errorResponse(
      error instanceof Error ? error.message : "Action Plan is invalid.",
      400,
    );
  }

  let controllerAuthorization: ControllerAuthorization;
  try {
    controllerAuthorization = parseControllerAuthorization(
      body.controllerAuthorization,
    );
  } catch (error) {
    return errorResponse(
      error instanceof Error
        ? error.message
        : "Controller authorization is invalid.",
      400,
    );
  }

  if (plan.agent.toLowerCase() !== demoAgent.toLowerCase()) {
    return errorResponse(
      "This signing route only supports the demo agent.",
      400,
    );
  }

  const actionDigest = hashActionPlan(plan);
  const now = BigInt(Math.floor(Date.now() / 1000));
  const maximumExpiry = now + BigInt(demoAgentAuthorizationMaxTtlSeconds);

  if (
    controllerAuthorization.actionDigest.toLowerCase() !==
    actionDigest.toLowerCase()
  ) {
    return errorResponse(
      "Controller authorization does not match this Action Plan.",
      401,
    );
  }
  if (controllerAuthorization.expiresAt <= now) {
    return errorResponse("Controller authorization has expired.", 401);
  }
  if (controllerAuthorization.expiresAt > maximumExpiry) {
    return errorResponse(
      "Controller authorization expiry is too far ahead.",
      401,
    );
  }

  let mandate: Awaited<ReturnType<typeof readMandate>>;
  let publicClient: ReturnType<typeof getPublicClient>;
  try {
    publicClient = getPublicClient();
    mandate = await readMandate(publicClient, plan.mandateId);

    if (mandate[3].toLowerCase() !== demoAgent.toLowerCase()) {
      return errorResponse("This Mandate does not use the demo agent.", 409);
    }
    if (Number(mandate[7]) !== 0) {
      return errorResponse("This Mandate is not active.", 409);
    }
  } catch {
    return errorResponse(
      "Unable to verify the Mandate on X Layer Testnet.",
      503,
    );
  }

  let controllerAuthorized = false;
  try {
    controllerAuthorized = await publicClient.verifyTypedData({
      address: mandate[1],
      domain: demoAgentAuthorizationDomain,
      types: demoAgentAuthorizationTypes,
      primaryType: "DemoAgentAuthorization",
      message: {
        mandateId: plan.mandateId,
        agent: plan.agent,
        actionDigest,
        expiresAt: controllerAuthorization.expiresAt,
      },
      signature: controllerAuthorization.signature,
    });
  } catch {
    return errorResponse(
      "Unable to verify controller authorization on X Layer Testnet.",
      503,
    );
  }

  if (!controllerAuthorized) {
    return errorResponse(
      "Controller authorization does not match this Mandate.",
      401,
    );
  }

  const privateKey = process.env.DEMO_AGENT_PRIVATE_KEY;
  if (!privateKey) {
    return errorResponse("The demo agent signer is not configured.", 503);
  }
  if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    return errorResponse("The demo agent signer is misconfigured.", 500);
  }

  let account;
  try {
    account = privateKeyToAccount(privateKey as Hex);
  } catch {
    return errorResponse("The demo agent signer is misconfigured.", 500);
  }

  if (account.address.toLowerCase() !== demoAgent.toLowerCase()) {
    return errorResponse(
      "The demo agent signer does not match its address.",
      500,
    );
  }

  try {
    const signature = await account.signTypedData({
      domain: actionPlanDomain,
      types: actionTypes,
      primaryType: "ActionPlan",
      message: plan,
    });

    return NextResponse.json({ signature });
  } catch {
    return errorResponse(
      "The demo agent could not sign this Action Plan.",
      500,
    );
  }
}
