"use client";

import { useState } from "react";

type Filter = "all" | "vaults" | "mandates" | "agent" | "escalations";

const filters: { value: Filter; label: string }[] = [
  { value: "all", label: "All" },
  { value: "vaults", label: "Vaults" },
  { value: "mandates", label: "Mandates" },
  { value: "agent", label: "Agent" },
  { value: "escalations", label: "Escalations" },
];

export default function AppActivity() {
  const [filter, setFilter] = useState<Filter>("all");

  return (
    <>
      <div className="app-page-header">
        <h1>Activity</h1>
        <p>
          Onchain events from your Vaults, Mandates, agent actions, and
          escalations.
        </p>
      </div>

      <div className="app-tabs">
        {filters.map((f) => (
          <button
            key={f.value}
            type="button"
            className={`app-tab${filter === f.value ? " active" : ""}`}
            onClick={() => setFilter(f.value)}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="app-empty">
        <div className="app-empty-icon">📋</div>
        <h3>No activity yet</h3>
        <p>
          Events will appear here as you create Vaults, issue Mandates, execute
          actions, and manage escalations.
        </p>
      </div>
    </>
  );
}
