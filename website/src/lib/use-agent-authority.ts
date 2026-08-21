"use client";

import type { Address } from "viem";
import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import {
  addresses,
  chainId,
  grantlineAbi,
  mandateRegistryAbi,
} from "./contracts";
import type { MandateData, MandateRules, PreflightRules } from "./use-mandates";

export type AuthorityLineageStatus =
  "Active" | "Paused" | "Revoked" | "Not yet valid" | "Expired" | "Inactive";

export type AuthorityMandate = {
  mandate: MandateData;
  lineage: MandateData[];
  lineageActive: boolean;
  lineageStatus: AuthorityLineageStatus;
  effectiveRules: MandateRules | null;
  effectivePreflightRules: PreflightRules | null;
  effectiveValidAfter: bigint;
  effectiveValidUntil: bigint;
};

function mapMandate(result: readonly unknown[]): MandateData {
  return {
    id: result[0] as bigint,
    controller: result[1] as Address,
    vault: result[2] as Address,
    agent: result[3] as Address,
    createdBy: result[4] as Address,
    parentMandateId: result[5] as bigint,
    delegationDepth: Number(result[6]),
    status: Number(result[7]),
    rules: result[8] as MandateRules,
    preflightRules: result[9] as PreflightRules,
    validAfter: result[10] as bigint,
    validUntil: result[11] as bigint,
    createdAt: result[12] as bigint,
    revokedAt: result[13] as bigint,
  };
}

function getLineageStatus(
  lineage: MandateData[],
  lineageActive: boolean,
  validAfter: bigint,
  validUntil: bigint,
  chainTimestamp: bigint,
): AuthorityLineageStatus {
  if (lineageActive) return "Active";
  if (lineage.some((mandate) => mandate.status === 2)) return "Revoked";
  if (lineage.some((mandate) => mandate.status === 1)) return "Paused";

  if (validAfter > chainTimestamp) return "Not yet valid";
  if (validUntil !== 0n && validUntil < chainTimestamp) return "Expired";
  return "Inactive";
}

export function useAgentAuthority({
  agent,
  enabled = true,
}: {
  agent: Address | null;
  enabled?: boolean;
}) {
  const publicClient = usePublicClient({ chainId });

  const query = useQuery({
    queryKey: ["agent-authority", chainId, agent],
    queryFn: async (): Promise<AuthorityMandate[]> => {
      if (!publicClient || !agent) return [];

      const latestBlock = await publicClient.getBlock();
      const count = await publicClient.readContract({
        address: addresses.mandateRegistry,
        abi: mandateRegistryAbi,
        functionName: "agentMandateCount",
        args: [agent],
      });
      const ids = await Promise.all(
        Array.from({ length: Number(count) }, (_, index) =>
          publicClient.readContract({
            address: addresses.mandateRegistry,
            abi: mandateRegistryAbi,
            functionName: "agentMandateAt",
            args: [agent, BigInt(index)],
          }),
        ),
      );

      if (ids.length === 0) return [];

      const directResults = await Promise.all(
        ids.map((id) =>
          publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "getMandate",
            args: [id],
          }),
        ),
      );
      const directMandates = directResults.map(mapMandate);

      const lineageIds = await Promise.all(
        directMandates.map((mandate) =>
          publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "getLineage",
            args: [mandate.id],
          }),
        ),
      );
      const allLineageIds = [
        ...new Set(lineageIds.flat().map((id) => id.toString())),
      ].map((id) => BigInt(id));
      const directById = new Map(
        directMandates.map((mandate) => [mandate.id.toString(), mandate]),
      );
      const missingLineageIds = allLineageIds.filter(
        (id) => !directById.has(id.toString()),
      );
      const missingResults = await Promise.all(
        missingLineageIds.map((id) =>
          publicClient.readContract({
            address: addresses.grantline,
            abi: grantlineAbi,
            functionName: "getMandate",
            args: [id],
          }),
        ),
      );
      const mandatesById = new Map(
        [...directMandates, ...missingResults.map(mapMandate)].map(
          (mandate) => [mandate.id.toString(), mandate],
        ),
      );

      const enriched = await Promise.all(
        directMandates.map(async (mandate, index) => {
          const lineage = lineageIds[index].map((id) =>
            mandatesById.get(id.toString()),
          );
          if (lineage.some((item) => !item)) {
            throw new Error("Mandate lineage is incomplete.");
          }
          const completeLineage = lineage as MandateData[];
          const [lineageActive, validity] = await Promise.all([
            publicClient.readContract({
              address: addresses.grantline,
              abi: grantlineAbi,
              functionName: "isLineageActive",
              args: [mandate.id],
            }),
            publicClient.readContract({
              address: addresses.grantline,
              abi: grantlineAbi,
              functionName: "getEffectiveValidityWindow",
              args: [mandate.id],
            }),
          ]);
          let effectiveRules: MandateRules | null = null;
          let effectivePreflightRules: PreflightRules | null = null;

          if (lineageActive) {
            [effectiveRules, effectivePreflightRules] = (await Promise.all([
              publicClient.readContract({
                address: addresses.grantline,
                abi: grantlineAbi,
                functionName: "getEffectiveRules",
                args: [mandate.id],
              }),
              publicClient.readContract({
                address: addresses.grantline,
                abi: grantlineAbi,
                functionName: "getEffectivePreflightRules",
                args: [mandate.id],
              }),
            ])) as [MandateRules, PreflightRules];
          }

          return {
            mandate,
            lineage: completeLineage,
            lineageActive,
            lineageStatus: getLineageStatus(
              completeLineage,
              lineageActive,
              validity[0],
              validity[1],
              latestBlock.timestamp,
            ),
            effectiveRules,
            effectivePreflightRules,
            effectiveValidAfter: validity[0],
            effectiveValidUntil: validity[1],
          };
        }),
      );

      return enriched.sort((left, right) => {
        const activeOrder =
          Number(right.lineageActive) - Number(left.lineageActive);
        if (activeOrder !== 0) return activeOrder;
        if (left.mandate.id === right.mandate.id) return 0;
        return left.mandate.id > right.mandate.id ? -1 : 1;
      });
    },
    enabled: enabled && !!publicClient && !!agent,
    refetchInterval: 10_000,
  });

  return {
    mandates: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error
      ? "Failed to load authority from X Layer Testnet."
      : null,
    refetch: query.refetch,
  };
}
