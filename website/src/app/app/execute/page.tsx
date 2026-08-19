"use client";

import { useState } from "react";

type ActionTab = "transfer" | "swap";

export default function AppExecute() {
  const [tab, setTab] = useState<ActionTab>("transfer");

  return (
    <>
      <div className="app-page-header">
        <h1>Execute</h1>
        <p>Sign an Action Plan and submit it for Grantline&apos;s authority review.</p>
      </div>

      <div className="app-tabs">
        <button
          type="button"
          className={`app-tab${tab === "transfer" ? " active" : ""}`}
          onClick={() => setTab("transfer")}
        >
          TRANSFER
        </button>
        <button
          type="button"
          className={`app-tab${tab === "swap" ? " active" : ""}`}
          onClick={() => setTab("swap")}
        >
          SWAP
        </button>
      </div>

      <div className="app-card">
        {tab === "transfer" ? (
          <>
            <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>
              Transfer native token
            </h3>
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="transfer-to">
                Recipient
              </label>
              <input
                id="transfer-to"
                className="app-form-input"
                placeholder="0x..."
              />
            </div>
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="transfer-amount">
                Amount (OKB)
              </label>
              <input
                id="transfer-amount"
                className="app-form-input"
                placeholder="0.001"
              />
            </div>
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="transfer-nonce">
                Nonce
              </label>
              <input
                id="transfer-nonce"
                className="app-form-input"
                placeholder="1"
              />
            </div>
            <button
              type="button"
              className="app-btn app-btn-primary"
            >
              Sign and execute
            </button>
          </>
        ) : (
          <>
            <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>
              Swap tokens
            </h3>
            <div className="app-empty" style={{ padding: 32 }}>
              <p style={{ margin: 0, fontSize: 14 }}>
                SWAP execution requires a configured Uniswap V3 adapter on the
                deployment.
              </p>
            </div>
          </>
        )}
      </div>
    </>
  );
}
