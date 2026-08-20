"use client";

import { useReadContracts } from "wagmi";
import {
  addresses,
  chainId,
  grantlineAbi,
  mandateRegistryAbi,
} from "./contracts";

export function useProtocolStats() {
  const { data, isLoading, isError } = useReadContracts({
    contracts: [
      {
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "vaultCount",
        chainId,
      },
      {
        address: addresses.mandateRegistry,
        abi: mandateRegistryAbi,
        functionName: "mandateCount",
        chainId,
      },
    ],
  });

  return {
    vaults: Number((data?.[0]?.result as bigint) ?? BigInt(0)),
    mandates: Number((data?.[1]?.result as bigint) ?? BigInt(0)),
    isLoading,
    error: isError
      ? "Could not load protocol totals from X Layer Testnet."
      : null,
  };
}
