"use client";

import Link from "next/link";
import { useConnection, useConnect, useConnectors } from "wagmi";
import { useProtocolStats } from "@/lib/use-protocol-stats";

export default function AppDashboard() {
  const { isConnected } = useConnection();
  const connect = useConnect();
  const connectors = useConnectors();
  const stats = useProtocolStats();

  return (
    <>
      <div className="app-page-header">
        <h1>Dashboard</h1>
        <p>
          Where you create Vaults, attach agents, and execute actions through
          the authority layer.
        </p>
      </div>

      {!isConnected && (
        <div
          className="app-card"
          style={{ marginBottom: 24, textAlign: "center", padding: 48 }}
        >
          <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>
            Connect your wallet
          </h3>
          <p style={{ margin: 0, color: "#9a9896", fontSize: 14 }}>
            Connect a wallet to start exploring Grantline.
          </p>
        </div>
      )}

      <div className="app-stats">
        <div className="app-stat">
          <div className="app-stat-label">Vaults</div>
          <div className="app-stat-value">
            {stats.isLoading ? "---" : stats.vaults}
          </div>
        </div>
        <div className="app-stat">
          <div className="app-stat-label">Mandates</div>
          <div className="app-stat-value">
            {stats.isLoading ? "---" : stats.mandates}
          </div>
        </div>
      </div>

      <div className="app-card">
        <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>Getting started</h3>
        <ol className="app-steps">
          <li className="app-step">
            <span className="app-step-num">1</span>
            {isConnected ? (
              <span>Connect your wallet to X Layer testnet</span>
            ) : (
              <button
                type="button"
                className="app-step-link"
                style={{
                  background: "none",
                  border: "none",
                  padding: 0,
                  cursor:
                    connect.isPending || !connectors[0] ? "default" : "pointer",
                  opacity: connect.isPending || !connectors[0] ? 0.5 : 1,
                  font: "inherit",
                  textAlign: "left",
                }}
                disabled={connect.isPending || !connectors[0]}
                onClick={() => {
                  if (connectors[0]) {
                    connect.mutate({ connector: connectors[0] });
                  }
                }}
              >
                {connect.isPending
                  ? "Connecting…"
                  : "Connect your wallet to X Layer testnet"}
              </button>
            )}
          </li>
          <li className="app-step">
            <span className="app-step-num">2</span>
            <Link href="/app/vaults" className="app-step-link">
              Create a Vault and fund it with OKB
            </Link>
          </li>
          <li className="app-step">
            <span className="app-step-num">3</span>
            <Link href="/app/mandates" className="app-step-link">
              Create a Mandate and assign an agent
            </Link>
          </li>
          <li className="app-step">
            <span className="app-step-num">4</span>
            <Link href="/app/execute" className="app-step-link">
              Sign and execute an Action Plan
            </Link>
          </li>
          <li className="app-step">
            <span className="app-step-num">5</span>
            <span>Observe the authority check</span>
          </li>
        </ol>
      </div>
    </>
  );
}
