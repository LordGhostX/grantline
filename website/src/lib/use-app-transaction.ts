"use client";

import { useCallback, useState } from "react";
import type { Abi, Address } from "viem";
import {
  useConnection,
  usePublicClient,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { chainId } from "./contracts";

export type AppWriteRequest = {
  address: Address;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
  value?: bigint;
};

export type AppTransactionOptions = {
  skipChainSwitch?: boolean;
};

export function useAppTransaction() {
  const { chainId: connectedChainId } = useConnection();
  const publicClient = usePublicClient({ chainId });
  const switchChainMutation = useSwitchChain();
  const writeMutation = useWriteContract();
  const [isConfirming, setIsConfirming] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const reset = useCallback(() => {
    setError(null);
    setIsConfirming(false);
    switchChainMutation.reset();
    writeMutation.reset();
  }, [switchChainMutation, writeMutation]);

  const submit = useCallback(
    async (
      request: AppWriteRequest,
      options: AppTransactionOptions = {},
    ) => {
      setError(null);
      switchChainMutation.reset();
      writeMutation.reset();

      try {
        if (!options.skipChainSwitch && connectedChainId !== chainId) {
          await switchChainMutation.mutateAsync({ chainId });
        }

        const hash = await writeMutation.mutateAsync({
          ...request,
          chainId,
        } as Parameters<typeof writeMutation.mutateAsync>[0]);
        setIsConfirming(true);

        if (publicClient) {
          const receipt = await publicClient.waitForTransactionReceipt({
            hash,
          });
          if (receipt.status === "reverted") {
            throw new Error("The transaction reverted on X Layer Testnet.");
          }
        }

        return hash;
      } catch (submissionError) {
        setError(submissionError);
        throw submissionError;
      } finally {
        setIsConfirming(false);
      }
    },
    [connectedChainId, publicClient, switchChainMutation, writeMutation],
  );

  return {
    submit,
    reset,
    isPending:
      switchChainMutation.isPending || writeMutation.isPending || isConfirming,
    isOnSupportedChain: connectedChainId === chainId,
    error: error ?? switchChainMutation.error ?? writeMutation.error ?? null,
  };
}
