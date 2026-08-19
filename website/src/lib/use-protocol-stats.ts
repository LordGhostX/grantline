"use client";

import { useReadContracts } from "wagmi";
import { addresses, grantlineAbi } from "./contracts";

export function useProtocolStats() {
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "vaultCount",
      },
      {
        address: addresses.mandateRegistry,
        abi: [
          {
            name: "mandateCount",
            type: "function",
            stateMutability: "view",
            inputs: [],
            outputs: [{ type: "uint256" }],
          },
        ] as const,
        functionName: "mandateCount",
      },
    ],
  });

  return {
    vaults: Number((data?.[0]?.result as bigint) ?? BigInt(0)),
    mandates: Number((data?.[1]?.result as bigint) ?? BigInt(0)),
    isLoading,
  };
}
