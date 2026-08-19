"use client";

import { useAccount } from "wagmi";

export default function AppDashboard() {
  const { isConnected } = useAccount();

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
        <div className="app-card" style={{ marginBottom: 24, textAlign: "center", padding: 48 }}>
          <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>Connect your wallet</h3>
          <p style={{ margin: 0, color: "#9a9896", fontSize: 14 }}>
            Connect a wallet to start exploring Grantline.
          </p>
        </div>
      )}

      <div className="app-stats">
        <div className="app-stat">
          <div className="app-stat-label">Vaults</div>
          <div className="app-stat-value">0</div>
        </div>
        <div className="app-stat">
          <div className="app-stat-label">Mandates</div>
          <div className="app-stat-value">0</div>
        </div>
        <div className="app-stat">
          <div className="app-stat-label">Escalations</div>
          <div className="app-stat-value">0</div>
        </div>
        <div className="app-stat">
          <div className="app-stat-label">Executions</div>
          <div className="app-stat-value">0</div>
        </div>
      </div>

      <div className="app-card">
        <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>Getting started</h3>
        <ol className="app-steps">
          <li className="app-step">
            <span className="app-step-num">1</span>
            <span>Connect your wallet to X Layer testnet</span>
          </li>
          <li className="app-step">
            <span className="app-step-num">2</span>
            <span>Create a Vault and fund it with OKB</span>
          </li>
          <li className="app-step">
            <span className="app-step-num">3</span>
            <span>Create a Mandate to define agent authority</span>
          </li>
          <li className="app-step">
            <span className="app-step-num">4</span>
            <span>Attach a demo agent to the Mandate</span>
          </li>
          <li className="app-step">
            <span className="app-step-num">5</span>
            <span>Execute a transfer and observe the authority check</span>
          </li>
        </ol>
      </div>
    </>
  );
}
