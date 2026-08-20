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
  scope?: "controller" | "all";
  enabled?: boolean;
};

export function useMandates({
  scope = "controller",
  enabled = true,
}: UseMandatesOptions = {}) {
  const { address } = useConnection();
  const publicClient = usePublicClient({ chainId });
  const controllerScoped = scope === "controller";

  const {
    data: mandates,
    isLoading,
    error: queryError,
    refetch,
  } = useQuery({
    queryKey: ["mandates", chainId, address, scope],
    queryFn: async (): Promise<MandateData[]> => {
      if (!publicClient || (controllerScoped && !address)) return [];

      const count = await publicClient.readContract({
        address: addresses.mandateRegistry,
        abi: mandateRegistryAbi,
        functionName: "mandateCount",
      });

      if (count === 0n) return [];

      const total = Number(count);
      const ids = Array.from({ length: total }, (_, i) => BigInt(i + 1));

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
        parentMandateId: r[4],
        delegationDepth: r[5],
        status: r[6],
        rules: r[7],
        preflightRules: r[8],
        validAfter: r[9],
        validUntil: r[10],
        createdAt: r[11],
        revokedAt: r[12],
      })) as MandateData[];

      if (!controllerScoped || !address) return allMandates;
      return allMandates.filter(
        (mandate) => mandate.controller.toLowerCase() === address.toLowerCase(),
      );
    },
    enabled: enabled && !!publicClient && (!controllerScoped || !!address),
    refetchInterval: 10_000,
  });

  return {
    mandates: mandates ?? [],
    isLoading,
    error: queryError ? "Failed to load mandates from chain" : null,
    refetch,
  };
}
