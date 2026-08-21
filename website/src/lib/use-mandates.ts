"use client";

import type { Address } from "viem";
import { useConnection, usePublicClient } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import {
  addresses,
  chainId,
  grantlineAbi,
  mandateRegistryAbi,
} from "./contracts";

export interface MandateData {
  id: bigint;
  controller: Address;
  vault: Address;
  agent: Address;
  createdBy: Address;
  parentMandateId: bigint;
  delegationDepth: number;
  status: number;
  rules: {
    canDelegate: boolean;
    minNativeAmount: bigint;
    maxNativeAmount: bigint;
    escalateNativeAmount: boolean;
    minNativeUsd: bigint;
    maxNativeUsd: bigint;
    escalateNativeUsd: boolean;
  };
  preflightRules: {
    minNativeBalance: bigint;
    escalateNativeBalance: boolean;
    minNativeUsdBalance: bigint;
    escalateNativeUsdBalance: boolean;
  };
  validAfter: bigint;
  validUntil: bigint;
  createdAt: bigint;
  revokedAt: bigint;
}

export type MandateStatus = "Active" | "Paused" | "Revoked" | "Unknown";

export function getMandateStatusLabel(status: number): MandateStatus {
  switch (status) {
    case 0:
      return "Active";
    case 1:
      return "Paused";
    case 2:
      return "Revoked";
    default:
      return "Unknown";
  }
}

type UseMandatesOptions = {
  scope?: "controller" | "creator" | "agent" | "all";
  enabled?: boolean;
};

export function useMandates({
  scope = "controller",
  enabled = true,
}: UseMandatesOptions = {}) {
  const { address } = useConnection();
  const publicClient = usePublicClient({ chainId });
  const addressScoped = scope !== "all";

  const {
    data: mandates,
    isLoading,
    error: queryError,
    refetch,
  } = useQuery({
    queryKey: ["mandates", chainId, address, scope],
    queryFn: async (): Promise<MandateData[]> => {
      if (!publicClient || (addressScoped && !address)) return [];

      let ids: bigint[];
      if (scope === "all") {
        const count = await publicClient.readContract({
          address: addresses.mandateRegistry,
          abi: mandateRegistryAbi,
          functionName: "mandateCount",
        });
        ids = Array.from({ length: Number(count) }, (_, i) => BigInt(i + 1));
      } else if (scope === "creator" || scope === "agent") {
        const count = await publicClient.readContract({
          address: addresses.mandateRegistry,
          abi: mandateRegistryAbi,
          functionName:
            scope === "creator" ? "creatorMandateCount" : "agentMandateCount",
          args: [address!],
        });
        ids = await Promise.all(
          Array.from({ length: Number(count) }, (_, i) =>
            publicClient.readContract({
              address: addresses.mandateRegistry,
              abi: mandateRegistryAbi,
              functionName:
                scope === "creator" ? "creatorMandateAt" : "agentMandateAt",
              args: [address!, BigInt(i)],
            }),
          ),
        );
      } else {
        const vaultCount = await publicClient.readContract({
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "controllerVaultCount",
          args: [address!],
        });
        const vaults = await Promise.all(
          Array.from({ length: Number(vaultCount) }, (_, i) =>
            publicClient.readContract({
              address: addresses.grantline,
              abi: grantlineAbi,
              functionName: "controllerVaultAt",
              args: [address!, BigInt(i)],
            }),
          ),
        );
        const mandateIds = await Promise.all(
          vaults.map(async (vault) => {
            const count = await publicClient.readContract({
              address: addresses.mandateRegistry,
              abi: mandateRegistryAbi,
              functionName: "vaultMandateCount",
              args: [vault],
            });
            return Promise.all(
              Array.from({ length: Number(count) }, (_, i) =>
                publicClient.readContract({
                  address: addresses.mandateRegistry,
                  abi: mandateRegistryAbi,
                  functionName: "vaultMandateAt",
                  args: [vault, BigInt(i)],
                }),
              ),
            );
          }),
        );
        ids = mandateIds.flat();
      }

      if (ids.length === 0) return [];

      const results = await Promise.all(
        ids.map((id) =>
          publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "getMandate",
            args: [id],
          }),
        ),
      );

      const allMandates = results.map((r) => ({
        id: r[0],
        controller: r[1],
        vault: r[2],
        agent: r[3],
        createdBy: r[4],
        parentMandateId: r[5],
        delegationDepth: r[6],
        status: r[7],
        rules: r[8],
        preflightRules: r[9],
        validAfter: r[10],
        validUntil: r[11],
        createdAt: r[12],
        revokedAt: r[13],
      })) as MandateData[];

      return allMandates;
    },
    enabled: enabled && !!publicClient && (!addressScoped || !!address),
    refetchInterval: 10_000,
  });

  return {
    mandates: mandates ?? [],
    isLoading,
    error: queryError ? "Failed to load mandates from chain" : null,
    refetch,
  };
}
