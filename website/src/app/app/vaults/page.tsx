"use client";

export default function AppVaults() {
  return (
    <>
      <div className="app-page-header">
        <h1>Vaults</h1>
        <p>Create and manage Vault contracts that hold controlled capital.</p>
      </div>

      <div style={{ marginBottom: 24 }}>
        <button type="button" className="app-btn app-btn-primary">
          Create Vault
        </button>
      </div>

      <div className="app-empty">
        <div className="app-empty-icon">🏦</div>
        <h3>No vaults yet</h3>
        <p>Create a Vault to start holding capital under Grantline authority.</p>
      </div>
    </>
  );
}
