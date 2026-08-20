export const chainId = 1952;

export const demoAgent =
  "0x648ac3f9297d59089b02a6091da6dd76902a785b" as `0x${string}`;

export const addresses = {
  grantline: "0x47595f11570e97acf96fe9f7f9a02dd91488a4a0" as `0x${string}`,
  mandateRegistry:
    "0x20cef966b489a8fb467c879af498f2bd8083644c" as `0x${string}`,
  vaultFactory: "0x85f21601d1a38957d5d4e3fb862a85fdc0fba974" as `0x${string}`,
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
] as const;
