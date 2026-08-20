"use client";

import Link from "next/link";
import { useConnection, useConnect, useConnectors } from "wagmi";
import { useProtocolStats } from "@/lib/use-protocol-stats";
import { chainId } from "@/lib/contracts";

export default function AppDashboard() {
  const { isConnected, chainId: connectedChainId } = useConnection();
  const connect = useConnect();
  const connectors = useConnectors();
  const stats = useProtocolStats();

  return (
    <>
      <div className="app-page-header">
        <h1>Dashboard</h1>
        <p>
          Where you create Vaults, attach agents, and execute actions through
          Grantline&apos;s authority layer.
        </p>
      </div>

      {!isConnected && (
        <div className="app-card app-dashboard-callout">
          <div className="app-dashboard-callout-copy">
            <h2>Connect your wallet</h2>
            <p>
              Connect a wallet to create a testnet Vault and explore Grantline.
            </p>
          </div>
          <button
            type="button"
            className="app-btn app-btn-primary"
            disabled={connect.isPending || !connectors[0]}
            onClick={() => {
              if (connectors[0]) connect.mutate({ connector: connectors[0] });
            }}
          >
            {connect.isPending ? "Connecting…" : "Connect wallet"}
          </button>
        </div>
      )}

      {isConnected && connectedChainId !== chainId && (
        <div className="app-alert app-alert-warning" role="status">
          Switch to X Layer Testnet before creating or managing Vaults and
          Mandates.
        </div>
      )}

      <div className="app-stats">
        <div className="app-stat">
          <div className="app-stat-label">Total Grantline Vaults</div>
          <div className="app-stat-value" aria-live="polite">
            {stats.isLoading ? "---" : stats.vaults}
          </div>
        </div>
        <div className="app-stat">
          <div className="app-stat-label">Total Grantline Mandates</div>
          <div className="app-stat-value" aria-live="polite">
            {stats.isLoading ? "---" : stats.mandates}
          </div>
        </div>
      </div>

      {stats.error && (
        <div className="app-alert app-alert-error" role="alert">
          {stats.error}
        </div>
      )}

      <div className="app-card">
        <h2 className="app-card-title">Getting started</h2>
        <ol className="app-steps">
          <li className="app-step">
            <span className="app-step-num">1</span>
            {isConnected ? (
              <span>
                Wallet connected.{" "}
                {connectedChainId === chainId
                  ? "You are on X Layer Testnet."
                  : "Switch to X Layer Testnet to continue."}
              </span>
            ) : (
              <span>Connect your wallet to X Layer Testnet.</span>
            )}
          </li>
          <li className="app-step">
            <span className="app-step-num">2</span>
            <Link href="/app/vaults" className="app-step-link">
              Create a Vault and fund it with OKB.
            </Link>
          </li>
          <li className="app-step">
            <span className="app-step-num">3</span>
            <Link href="/app/mandates" className="app-step-link">
              Create a Mandate and assign an agent.
            </Link>
          </li>
          <li className="app-step">
            <span className="app-step-num">4</span>
            <Link href="/app/authority" className="app-step-link">
              Inspect the agent&apos;s authority.
            </Link>
          </li>
          <li className="app-step">
            <span className="app-step-num">5</span>
            <Link href="/app/execute" className="app-step-link">
              Sign and execute an Action Plan.
            </Link>
          </li>
        </ol>
      </div>
    </>
  );
}
