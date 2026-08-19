"use client";

export default function AppMandates() {
  return (
    <>
      <div className="app-page-header">
        <h1>Mandates</h1>
        <p>
          Define and manage the authority rules that govern agent actions.
        </p>
      </div>

      <div style={{ marginBottom: 24 }}>
        <button type="button" className="app-btn app-btn-primary">
          Create Mandate
        </button>
      </div>

      <div className="app-empty">
        <div className="app-empty-icon">📜</div>
        <h3>No mandates yet</h3>
        <p>
          Create a Mandate to define what an agent is allowed to do against a
          Vault.
        </p>
      </div>
    </>
  );
}
