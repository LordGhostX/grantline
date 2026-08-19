"use client";

export default function AppEscalations() {
  return (
    <>
      <div className="app-page-header">
        <h1>Escalations</h1>
        <p>
          Proposals that exceeded their authority and await controller review.
        </p>
      </div>

      <div className="app-empty">
        <div className="app-empty-icon">🔍</div>
        <h3>No escalations yet</h3>
        <p>
          When an Action Plan exceeds its authority, the proposal appears here
          for approval or denial.
        </p>
      </div>
    </>
  );
}
