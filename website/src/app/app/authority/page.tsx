"use client";

import { useState } from "react";
import { demoAgent } from "@/lib/contracts";

export default function AppAuthority() {
  const [address, setAddress] = useState<string>(demoAgent);

  return (
    <>
      <div className="app-page-header">
        <h1>Authority</h1>
        <p>
          Inspect an agent&apos;s effective authority, delegation tree, and
          Preflight rules.
        </p>
      </div>

      <div className="app-card" style={{ marginBottom: 24 }}>
        <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>
          Look up agent authority
        </h3>
        <div className="app-form-group">
          <label className="app-form-label" htmlFor="authority-address">
            Agent address
          </label>
          <div style={{ display: "flex", gap: 8 }}>
            <input
              id="authority-address"
              className="app-form-input"
              placeholder="0x..."
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              style={{ flex: 1 }}
            />
            <button type="button" className="app-btn app-btn-primary">
              Look up
            </button>
          </div>
          <p style={{ margin: "4px 0 0", fontSize: 12, color: "#5a5856" }}>
            Demo agent pre-filled. Look up its authority after creating a
            mandate for it.
          </p>
        </div>
      </div>

      <div className="app-card" style={{ marginBottom: 24 }}>
        <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>
          Effective authority
        </h3>
        <div className="app-empty" style={{ padding: 32 }}>
          <p style={{ margin: 0, fontSize: 14 }}>
            Enter an agent address to see what it can do, what it cannot do, and
            which Mandates govern its behaviour.
          </p>
        </div>
      </div>

      <div className="app-card" style={{ marginBottom: 24 }}>
        <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>Delegation tree</h3>
        <div className="app-empty" style={{ padding: 32 }}>
          <p style={{ margin: 0, fontSize: 14 }}>
            Shows the parent-to-child mandate lineage and how authority narrows
            at each level.
          </p>
        </div>
      </div>

      <div className="app-card">
        <h3 style={{ margin: "0 0 16px", fontSize: 16 }}>Preflight rules</h3>
        <div className="app-empty" style={{ padding: 32 }}>
          <p style={{ margin: 0, fontSize: 14 }}>
            Displays balance checks, native-USD reserve floors, and other
            pre-execution constraints that apply to this agent.
          </p>
        </div>
      </div>
    </>
  );
}
