"use client";

import { useReadContract } from "wagmi";
import { addresses, vaultFactoryAbi, mandateRegistryAbi } from "./contracts";

export function useProtocolStats() {
  const { data: vaultCount, isLoading: vaultsLoading } = useReadContract({
    address: addresses.vaultFactory,
    abi: vaultFactoryAbi,
    functionName: "vaultCount",
  });

  const { data: mandateCount, isLoading: mandatesLoading } = useReadContract({
    address: addresses.mandateRegistry,
    abi: mandateRegistryAbi,
    functionName: "mandateCount",
  });

  return {
    vaults: Number(vaultCount ?? BigInt(0)),
    mandates: Number(mandateCount ?? BigInt(0)),
    isLoading: vaultsLoading || mandatesLoading,
  };
}
