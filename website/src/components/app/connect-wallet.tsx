"use client";

import { useConnect, useAccount, useDisconnect } from "wagmi";

export function ConnectWallet() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending, error } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <button
        type="button"
        className="app-connect connected"
        onClick={() => disconnect()}
      >
        <span className="app-connect-dot" />
        {address.slice(0, 6)}…{address.slice(-4)}
      </button>
    );
  }

  return (
    <div className="app-connect-wrap">
      <button
        type="button"
        className="app-connect"
        disabled={isPending}
        onClick={() => connect({ connector: connectors[0] })}
      >
        {isPending ? "Connecting…" : "Connect wallet"}
      </button>
      {error && (
        <span className="app-connect-error">
          {"shortMessage" in error ? error.shortMessage : error.message}
        </span>
      )}
    </div>
  );
}
