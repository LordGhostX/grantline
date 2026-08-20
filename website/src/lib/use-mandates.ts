"use client";

import { type Hex, formatUnits } from "viem";
import { useAccount, usePublicClient } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import { addresses, grantlineAbi, mandateRegistryAbi } from "./contracts";

export interface MandateData {
  id: bigint;
  controller: Hex;
  vault: Hex;
  agent: Hex;
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

export function truncateHex(address: Hex): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatOkb(wei: bigint): string {
  const formatted = formatUnits(wei, 18);
  const num = parseFloat(formatted);
  if (num === 0) return "0";
  if (num < 0.001) return "<0.001";
  return num.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 4,
  });
}

export function useMandates() {
  const { address } = useAccount();
  const publicClient = usePublicClient();

  const {
    data: mandates,
    isLoading,
    error: queryError,
    refetch,
  } = useQuery({
    queryKey: ["mandates", address],
    queryFn: async (): Promise<MandateData[]> => {
      if (!publicClient || !address) return [];

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

      return results
        .map((r) => ({
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
        }))
        .filter(
          (m) => m.controller.toLowerCase() === address.toLowerCase(),
        ) as MandateData[];
    },
    enabled: !!publicClient && !!address,
    refetchInterval: 10_000,
  });

  return {
    mandates: mandates ?? [],
    isLoading,
    error: queryError ? "Failed to load mandates from chain" : null,
    refetch,
  };
}
