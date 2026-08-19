"use client";

import { useAccount, usePublicClient } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import { addresses, grantlineAbi } from "./contracts";

export type VaultInfo = {
  address: `0x${string}`;
  index: number;
  controller: `0x${string}`;
  owner: `0x${string}`;
  authority: `0x${string}`;
  implementation: `0x${string}`;
  version: number;
  nativeBalance: bigint;
  paused: boolean;
};

export function useVaults() {
  const { address: connectedAddress } = useAccount();
  const publicClient = usePublicClient();

  const {
    data: vaults,
    isLoading,
    refetch,
  } = useQuery({
    queryKey: ["vaults", connectedAddress],
    queryFn: async (): Promise<VaultInfo[]> => {
      if (!publicClient || !connectedAddress) return [];

      const count = await publicClient.readContract({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "vaultCount",
      });

      if (count === BigInt(0)) return [];

      const addresses_ = await Promise.all(
        Array.from({ length: Number(count) }, (_, i) =>
          publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "vaultAt",
            args: [BigInt(i)],
          }),
        ),
      );

      const views = await Promise.all(
        addresses_.map((addr) =>
          publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "getVault",
            args: [addr],
          }),
        ),
      );

      return views
        .map((v, i) => ({
          address: v[0],
          index: i + 1,
          controller: v[1],
          owner: v[2],
          authority: v[3],
          implementation: v[4],
          version: Number(v[5]),
          nativeBalance: v[6],
          paused: v[7],
        }))
        .filter(
          (v) => v.controller.toLowerCase() === connectedAddress.toLowerCase(),
        );
    },
    enabled: !!publicClient && !!connectedAddress,
    refetchInterval: 10_000,
  });

  return {
    vaults: vaults ?? [],
    isLoading,
    refetch,
  };
}
