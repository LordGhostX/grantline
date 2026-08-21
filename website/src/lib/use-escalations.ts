"use client";

import type { Address, Hex } from "viem";
import { useConnection, usePublicClient } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import {
  addresses,
  chainId,
  escalationManagerAbi,
  grantlineAbi,
} from "./contracts";

export type EscalationAction = {
  actionType: number;
  version: number;
  parameters: Hex;
};

export type EscalationData = {
  digest: Hex;
  vault: Address;
  plan: {
    mandateId: bigint;
    agent: Address;
    nonce: bigint;
    deadline: bigint;
    actions: EscalationAction[];
  };
  signature: Hex;
  submittedBy: Address;
  status: number;
  submittedAt: bigint;
};

export type EscalationStatus =
  "Pending" | "Approved" | "Denied" | "Executed" | "Unknown";

export function getEscalationStatusLabel(status: number): EscalationStatus {
  switch (status) {
    case 1:
      return "Pending";
    case 2:
      return "Approved";
    case 3:
      return "Denied";
    case 4:
      return "Executed";
    default:
      return "Unknown";
  }
}

type UseEscalationsOptions = {
  scope?: "controller" | "agent" | "all";
  enabled?: boolean;
};

function isActiveStatus(status: number): boolean {
  return status === 1 || status === 2;
}

export function useEscalations({
  scope = "controller",
  enabled = true,
}: UseEscalationsOptions = {}) {
  const { address } = useConnection();
  const publicClient = usePublicClient({ chainId });
  const addressScoped = scope !== "all";

  const {
    data: escalations,
    isLoading,
    error: queryError,
    refetch,
  } = useQuery({
    queryKey: ["escalations", chainId, address, scope],
    queryFn: async (): Promise<EscalationData[]> => {
      if (!publicClient || (addressScoped && !address)) return [];

      let digests: Hex[];
      if (scope === "all") {
        const count = await publicClient.readContract({
          address: addresses.escalationManager,
          abi: escalationManagerAbi,
          functionName: "escalationCount",
        });
        digests = await Promise.all(
          Array.from({ length: Number(count) }, (_, i) =>
            publicClient.readContract({
              address: addresses.escalationManager,
              abi: escalationManagerAbi,
              functionName: "escalationAt",
              args: [BigInt(i)],
            }),
          ),
        );
      } else if (scope === "agent") {
        const count = await publicClient.readContract({
          address: addresses.escalationManager,
          abi: escalationManagerAbi,
          functionName: "agentEscalationCount",
          args: [address!],
        });
        digests = await Promise.all(
          Array.from({ length: Number(count) }, (_, i) =>
            publicClient.readContract({
              address: addresses.escalationManager,
              abi: escalationManagerAbi,
              functionName: "agentEscalationAt",
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
        const scopedDigests = await Promise.all(
          vaults.map(async (vault) => {
            const count = await publicClient.readContract({
              address: addresses.escalationManager,
              abi: escalationManagerAbi,
              functionName: "vaultEscalationCount",
              args: [vault],
            });
            return Promise.all(
              Array.from({ length: Number(count) }, (_, i) =>
                publicClient.readContract({
                  address: addresses.escalationManager,
                  abi: escalationManagerAbi,
                  functionName: "vaultEscalationAt",
                  args: [vault, BigInt(i)],
                }),
              ),
            );
          }),
        );
        digests = scopedDigests.flat();
      }

      const uniqueDigests = [...new Set(digests)];
      const records = await Promise.all(
        uniqueDigests.map(async (digest) => {
          const record = await publicClient.readContract({
            address: addresses.escalationManager,
            abi: escalationManagerAbi,
            functionName: "getEscalation",
            args: [digest],
          });
          const mandate = await publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "getMandate",
            args: [record[0].mandateId],
          });

          return {
            digest,
            vault: mandate[2],
            plan: {
              mandateId: record[0].mandateId,
              agent: record[0].agent,
              nonce: record[0].nonce,
              deadline: record[0].deadline,
              actions: record[0].actions.map((action) => ({
                actionType: action.actionType,
                version: action.version,
                parameters: action.parameters,
              })),
            },
            signature: record[1],
            submittedBy: record[2],
            status: record[3],
            submittedAt: record[4],
          } as EscalationData;
        }),
      );

      return records.sort((left, right) => {
        const activeOrder =
          Number(isActiveStatus(left.status)) -
          Number(isActiveStatus(right.status));
        if (activeOrder !== 0) return -activeOrder;
        if (left.submittedAt !== right.submittedAt) {
          return left.submittedAt > right.submittedAt ? -1 : 1;
        }
        return left.digest.localeCompare(right.digest);
      });
    },
    enabled: enabled && !!publicClient && (!addressScoped || !!address),
    refetchInterval: 10_000,
  });

  return {
    escalations: escalations ?? [],
    isLoading,
    error: queryError
      ? "Failed to load Escalations from X Layer Testnet."
      : null,
    refetch,
  };
}
