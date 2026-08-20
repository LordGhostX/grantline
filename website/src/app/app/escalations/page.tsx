"use client";

import { useConnection } from "wagmi";
import GrantlineMark from "@/components/grantline-mark";

export default function AppEscalations() {
  const { isConnected } = useConnection();

  return (
    <>
      <div className="app-page-header">
        <h1>Escalations</h1>
        <p>
          Proposals that exceeded their authority and await controller review.
        </p>
      </div>

      <div className={isConnected ? "app-empty" : "app-empty app-card"}>
        <GrantlineMark className="app-empty-icon" />
        {isConnected ? (
          <>
            <h3>No escalations yet</h3>
            <p>
              When an Action Plan exceeds its authority, the proposal appears
              here for approval or denial.
            </p>
          </>
        ) : (
          <>
            <h2>Connect your wallet</h2>
            <p>Connect your wallet to review Mandate escalations.</p>
          </>
        )}
      </div>
    </>
  );
}
