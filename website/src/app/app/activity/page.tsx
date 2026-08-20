"use client";

import { useState } from "react";
import { useConnection } from "wagmi";
import GrantlineMark from "@/components/grantline-mark";

type Filter = "all" | "vaults" | "mandates" | "agent" | "escalations";

const filters: { value: Filter; label: string }[] = [
  { value: "all", label: "All" },
  { value: "vaults", label: "Vaults" },
  { value: "mandates", label: "Mandates" },
  { value: "agent", label: "Agent" },
  { value: "escalations", label: "Escalations" },
];

export default function AppActivity() {
  const { isConnected } = useConnection();
  const [filter, setFilter] = useState<Filter>("all");
  const activeFilter = filters.find((item) => item.value === filter);

  return (
    <>
      <div className="app-page-header">
        <h1>Activity</h1>
        <p>
          Onchain events from your Vaults, Mandates, agent actions, and
          escalations.
        </p>
      </div>

      {!isConnected ? (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>Connect your wallet</h2>
          <p>Connect your wallet to view your Grantline activity.</p>
        </div>
      ) : (
        <>
          <div className="app-tabs">
            {filters.map((f) => (
              <button
                key={f.value}
                type="button"
                aria-pressed={filter === f.value}
                className={`app-tab${filter === f.value ? " active" : ""}`}
                onClick={() => setFilter(f.value)}
              >
                {f.label}
              </button>
            ))}
          </div>

          <div className="app-empty">
            <GrantlineMark className="app-empty-icon" />
            <h3>
              No{" "}
              {activeFilter?.value === "all" ? "" : `${activeFilter?.label} `}
              activity yet
            </h3>
            <p>
              Events will appear here as you create Vaults, issue Mandates,
              execute actions, and manage escalations.
            </p>
          </div>
        </>
      )}
    </>
  );
}
