import { getAddress, isAddress, type Address } from "viem";
import deployment from "../../data/deployments/xlayer-testnet.json";

export const chainId = 1952 as const;

if (deployment.chainId !== chainId) {
  throw new Error(
    "The website X Layer deployment manifest has the wrong chain ID",
  );
}

const configuredDemoAgent = process.env.NEXT_PUBLIC_DEMO_AGENT_ADDRESS;

if (!configuredDemoAgent || !isAddress(configuredDemoAgent)) {
  throw new Error(
    "NEXT_PUBLIC_DEMO_AGENT_ADDRESS must be a valid Ethereum address",
  );
}

export const demoAgent = getAddress(configuredDemoAgent);

const configuredExplorerUrl =
  process.env.NEXT_PUBLIC_XLAYER_TESTNET_EXPLORER_URL?.trim();

if (!configuredExplorerUrl || !/^https?:\/\//i.test(configuredExplorerUrl)) {
  throw new Error(
    "NEXT_PUBLIC_XLAYER_TESTNET_EXPLORER_URL must be a valid HTTP URL",
  );
}

export const xLayerTestnetExplorerUrl = configuredExplorerUrl.replace(
  /\/+$/,
  "",
);

export const addresses = {
  grantline: deployment.grantline.proxy as Address,
  mandateRegistry: deployment.modules.registry.proxy as Address,
  escalationManager: deployment.modules.escalationManager.proxy as Address,
  vaultFactory: deployment.modules.vaultFactory.proxy as Address,
} as const;

export const grantlineAbi = [
  {
    name: "createVault",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ type: "address", name: "vault" }],
  },
  {
    name: "vaultCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "vaultAt",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "index", type: "uint256" }],
    outputs: [{ type: "address" }],
  },
  {
    name: "controllerVaultCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "controller", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "controllerVaultAt",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "controller", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ type: "address" }],
  },
  {
    name: "getVault",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [
      { name: "vault_", type: "address" },
      { name: "controller", type: "address" },
      { name: "owner", type: "address" },
      { name: "authority", type: "address" },
      { name: "implementation", type: "address" },
      { name: "version", type: "uint64" },
      { name: "nativeBalance", type: "uint256" },
      { name: "paused", type: "bool" },
    ],
  },
  {
    name: "depositNative",
    type: "function",
    stateMutability: "payable",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [],
  },
  {
    name: "withdrawNative",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "vault", type: "address" },
      { name: "recipient", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "pauseVault",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [],
  },
  {
    name: "unpauseVault",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [],
  },
  {
    name: "VaultCreated",
    type: "event",
    inputs: [
      { name: "vault", type: "address", indexed: true },
      { name: "controller", type: "address", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "authority", type: "address", indexed: false },
      { name: "implementation", type: "address", indexed: false },
      { name: "version", type: "uint64", indexed: false },
    ],
  },
  {
    name: "createMandate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "vault", type: "address" },
      { name: "agent", type: "address" },
      {
        name: "rules",
        type: "tuple",
        components: [
          { name: "canDelegate", type: "bool" },
          { name: "minNativeAmount", type: "uint256" },
          { name: "maxNativeAmount", type: "uint256" },
          { name: "escalateNativeAmount", type: "bool" },
          { name: "minNativeUsd", type: "uint256" },
          { name: "maxNativeUsd", type: "uint256" },
          { name: "escalateNativeUsd", type: "bool" },
        ],
      },
      {
        name: "preflightRules",
        type: "tuple",
        components: [
          { name: "minNativeBalance", type: "uint256" },
          { name: "escalateNativeBalance", type: "bool" },
          { name: "minNativeUsdBalance", type: "uint256" },
          { name: "escalateNativeUsdBalance", type: "bool" },
        ],
      },
      { name: "validAfter", type: "uint64" },
      { name: "validUntil", type: "uint64" },
    ],
    outputs: [{ name: "mandateId", type: "uint256" }],
  },
  {
    name: "getMandate",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [
      { name: "id", type: "uint256" },
      { name: "controller", type: "address" },
      { name: "vault", type: "address" },
      { name: "agent", type: "address" },
      { name: "createdBy", type: "address" },
      { name: "parentMandateId", type: "uint256" },
      { name: "delegationDepth", type: "uint8" },
      { name: "status", type: "uint8" },
      {
        name: "rules",
        type: "tuple",
        components: [
          { name: "canDelegate", type: "bool" },
          { name: "minNativeAmount", type: "uint256" },
          { name: "maxNativeAmount", type: "uint256" },
          { name: "escalateNativeAmount", type: "bool" },
          { name: "minNativeUsd", type: "uint256" },
          { name: "maxNativeUsd", type: "uint256" },
          { name: "escalateNativeUsd", type: "bool" },
        ],
      },
      {
        name: "preflightRules",
        type: "tuple",
        components: [
          { name: "minNativeBalance", type: "uint256" },
          { name: "escalateNativeBalance", type: "bool" },
          { name: "minNativeUsdBalance", type: "uint256" },
          { name: "escalateNativeUsdBalance", type: "bool" },
        ],
      },
      { name: "validAfter", type: "uint64" },
      { name: "validUntil", type: "uint64" },
      { name: "createdAt", type: "uint64" },
      { name: "revokedAt", type: "uint64" },
    ],
  },
  {
    name: "getLineage",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [{ name: "lineage", type: "uint256[]" }],
  },
  {
    name: "getEffectiveRules",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [
      {
        name: "rules",
        type: "tuple",
        components: [
          { name: "canDelegate", type: "bool" },
          { name: "minNativeAmount", type: "uint256" },
          { name: "maxNativeAmount", type: "uint256" },
          { name: "escalateNativeAmount", type: "bool" },
          { name: "minNativeUsd", type: "uint256" },
          { name: "maxNativeUsd", type: "uint256" },
          { name: "escalateNativeUsd", type: "bool" },
        ],
      },
    ],
  },
  {
    name: "getEffectivePreflightRules",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [
      {
        name: "preflightRules",
        type: "tuple",
        components: [
          { name: "minNativeBalance", type: "uint256" },
          { name: "escalateNativeBalance", type: "bool" },
          { name: "minNativeUsdBalance", type: "uint256" },
          { name: "escalateNativeUsdBalance", type: "bool" },
        ],
      },
    ],
  },
  {
    name: "getEffectiveValidityWindow",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [
      { name: "validAfter", type: "uint64" },
      { name: "validUntil", type: "uint64" },
    ],
  },
  {
    name: "isLineageActive",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [{ name: "active", type: "bool" }],
  },
  {
    name: "pauseMandate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [],
  },
  {
    name: "unpauseMandate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [],
  },
  {
    name: "revokeMandate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "mandateId", type: "uint256" }],
    outputs: [],
  },
  {
    name: "evaluate",
    type: "function",
    stateMutability: "view",
    inputs: [
      {
        name: "plan",
        type: "tuple",
        components: [
          { name: "mandateId", type: "uint256" },
          { name: "agent", type: "address" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
          {
            name: "actions",
            type: "tuple[]",
            components: [
              { name: "actionType", type: "uint8" },
              { name: "version", type: "uint8" },
              { name: "parameters", type: "bytes" },
            ],
          },
        ],
      },
      { name: "signature", type: "bytes" },
    ],
    outputs: [
      {
        name: "result",
        type: "tuple",
        components: [
          { name: "decision", type: "uint8" },
          { name: "failureCode", type: "uint8" },
          { name: "failedActionIndex", type: "uint256" },
          { name: "nativeAmount", type: "uint256" },
          { name: "nativeUsdValue", type: "uint256" },
          { name: "nativeBalanceAfter", type: "uint256" },
          { name: "nativeBalanceUsdValue", type: "uint256" },
        ],
      },
    ],
  },
  {
    name: "submitEscalation",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "plan",
        type: "tuple",
        components: [
          { name: "mandateId", type: "uint256" },
          { name: "agent", type: "address" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
          {
            name: "actions",
            type: "tuple[]",
            components: [
              { name: "actionType", type: "uint8" },
              { name: "version", type: "uint8" },
              { name: "parameters", type: "bytes" },
            ],
          },
        ],
      },
      { name: "signature", type: "bytes" },
    ],
    outputs: [{ name: "digest", type: "bytes32" }],
  },
  {
    name: "approveEscalation",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "digest", type: "bytes32" }],
    outputs: [],
  },
  {
    name: "denyEscalation",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "digest", type: "bytes32" }],
    outputs: [],
  },
  {
    name: "executeEscalated",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "digest", type: "bytes32" }],
    outputs: [],
  },
  {
    name: "execute",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "plan",
        type: "tuple",
        components: [
          { name: "mandateId", type: "uint256" },
          { name: "agent", type: "address" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
          {
            name: "actions",
            type: "tuple[]",
            components: [
              { name: "actionType", type: "uint8" },
              { name: "version", type: "uint8" },
              { name: "parameters", type: "bytes" },
            ],
          },
        ],
      },
      { name: "signature", type: "bytes" },
    ],
    outputs: [{ name: "digest", type: "bytes32" }],
  },
] as const;

export const vaultFactoryAbi = [
  {
    name: "vaultCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;

export const mandateRegistryAbi = [
  {
    name: "mandateCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "vaultMandateCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "vaultMandateAt",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "vault", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "creatorMandateCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "creator", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "creatorMandateAt",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "creator", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "agentMandateCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "agentMandateAt",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "agent", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const;

export const escalationManagerAbi = [
  {
    name: "escalationCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "escalationAt",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "index", type: "uint256" }],
    outputs: [{ type: "bytes32" }],
  },
  {
    name: "vaultEscalationCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "vaultEscalationAt",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "vault", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ type: "bytes32" }],
  },
  {
    name: "agentEscalationCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "agentEscalationAt",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "agent", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ type: "bytes32" }],
  },
  {
    name: "getEscalation",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "digest", type: "bytes32" }],
    outputs: [
      {
        name: "escalation",
        type: "tuple",
        components: [
          {
            name: "plan",
            type: "tuple",
            components: [
              { name: "mandateId", type: "uint256" },
              { name: "agent", type: "address" },
              { name: "nonce", type: "uint256" },
              { name: "deadline", type: "uint256" },
              {
                name: "actions",
                type: "tuple[]",
                components: [
                  { name: "actionType", type: "uint8" },
                  { name: "version", type: "uint8" },
                  { name: "parameters", type: "bytes" },
                ],
              },
            ],
          },
          { name: "signature", type: "bytes" },
          { name: "submittedBy", type: "address" },
          { name: "status", type: "uint8" },
          { name: "submittedAt", type: "uint64" },
        ],
      },
    ],
  },
] as const;
