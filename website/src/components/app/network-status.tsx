"use client";

import { useConnection, useSwitchChain } from "wagmi";
import { chainId } from "@/lib/contracts";
import { formatError } from "@/lib/app-utils";

export function NetworkStatus() {
  const { isConnected, chainId: connectedChainId } = useConnection();
  const { mutateAsync: switchChainAsync, isPending, error } = useSwitchChain();

  async function handleSwitch() {
    try {
      await switchChainAsync({ chainId });
    } catch {
      // The mutation error is rendered below.
    }
  }

  if (!isConnected) {
    return (
      <div
        className="app-network app-network-muted"
        role="status"
        aria-label="Wallet not connected"
        title="Wallet not connected"
      >
        <span className="app-network-dot" aria-hidden="true" />
        <span className="app-network-label">Wallet not connected</span>
      </div>
    );
  }

  if (connectedChainId === chainId) {
    return (
      <div
        className="app-network"
        role="status"
        aria-label="Connected to X Layer Testnet"
        title="Connected to X Layer Testnet"
      >
        <span className="app-network-dot" aria-hidden="true" />
        <span className="app-network-label">X Layer Testnet</span>
      </div>
    );
  }

  return (
    <div className="app-network-wrap">
      <button
        type="button"
        className="app-network app-network-wrong"
        onClick={() => void handleSwitch()}
        disabled={isPending}
      >
        <span className="app-network-dot" aria-hidden="true" />
        <span className="app-network-label">
          {isPending ? "Switching network…" : "Switch to X Layer Testnet"}
        </span>
      </button>
      {error && <span className="app-network-error">{formatError(error)}</span>}
    </div>
  );
}
