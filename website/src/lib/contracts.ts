export const addresses = {
  mandateRegistry: "0x20cef966b489a8fb467c879af498f2bd8083644c" as `0x${string}`,
  vaultFactory: "0x85f21601d1a38957d5d4e3fb862a85fdc0fba974" as `0x${string}`,
} as const;

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


