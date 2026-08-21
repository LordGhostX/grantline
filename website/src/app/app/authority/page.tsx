"use client";

import { useState, type FormEvent } from "react";
import { isAddress, type Address } from "viem";
import { CopyAddress } from "@/components/app/copy-address";
import GrantlineMark from "@/components/grantline-mark";
import { demoAgent } from "@/lib/contracts";
import { formatDate, formatNative, truncateAddress } from "@/lib/app-utils";
import {
  type AuthorityLineageStatus,
  type AuthorityMandate,
  useAgentAuthority,
} from "@/lib/use-agent-authority";
import type { MandateRules, PreflightRules } from "@/lib/use-mandates";

function statusClass(status: AuthorityLineageStatus): string {
  if (status === "Active") return "app-tag-active";
  if (status === "Paused" || status === "Not yet valid") {
    return "app-tag-paused";
  }
  return "app-tag-revoked";
}

function nativeLimit(value: bigint, isMaximum = false): string {
  if (value === 0n) return isMaximum ? "No cap" : "None";
  return `${formatNative(value)} OKB`;
}

function usdLimit(value: bigint, isMaximum = false): string {
  if (value === 0n) return isMaximum ? "No cap" : "None";
  return `$${value.toLocaleString("en-US")}`;
}

function escalationLabel(enabled: boolean): string {
  return enabled ? "Escalate" : "Deny";
}

function validityLabel(after: bigint, until: bigint): string {
  if (after === 0n && until === 0n) return "Any time";
  return `${formatDate(after)} – ${formatDate(until)}`;
}

function AuthorityRules({ rules }: { rules: MandateRules }) {
  return (
    <dl className="app-authority-rule-grid">
      <div>
        <dt>Native amount floor</dt>
        <dd>{nativeLimit(rules.minNativeAmount)}</dd>
      </div>
      <div>
        <dt>Native amount cap</dt>
        <dd>{nativeLimit(rules.maxNativeAmount, true)}</dd>
      </div>
      <div>
        <dt>Amount breach</dt>
        <dd>{escalationLabel(rules.escalateNativeAmount)}</dd>
      </div>
      <div>
        <dt>Native-USD floor</dt>
        <dd>{usdLimit(rules.minNativeUsd)}</dd>
      </div>
      <div>
        <dt>Native-USD cap</dt>
        <dd>{usdLimit(rules.maxNativeUsd, true)}</dd>
      </div>
      <div>
        <dt>USD breach</dt>
        <dd>{escalationLabel(rules.escalateNativeUsd)}</dd>
      </div>
      <div>
        <dt>Delegation</dt>
        <dd>{rules.canDelegate ? "Allowed" : "Disabled"}</dd>
      </div>
    </dl>
  );
}

function PreflightRules({ rules }: { rules: PreflightRules }) {
  return (
    <dl className="app-authority-rule-grid">
      <div>
        <dt>Native balance reserve</dt>
        <dd>{nativeLimit(rules.minNativeBalance)}</dd>
      </div>
      <div>
        <dt>Reserve breach</dt>
        <dd>{escalationLabel(rules.escalateNativeBalance)}</dd>
      </div>
      <div>
        <dt>Native-USD reserve</dt>
        <dd>{usdLimit(rules.minNativeUsdBalance)}</dd>
      </div>
      <div>
        <dt>USD reserve breach</dt>
        <dd>{escalationLabel(rules.escalateNativeUsdBalance)}</dd>
      </div>
    </dl>
  );
}

function MandateSelector({
  items,
  selectedId,
  onSelect,
}: {
  items: AuthorityMandate[];
  selectedId: bigint;
  onSelect: (id: bigint) => void;
}) {
  return (
    <section className="app-card app-authority-selector">
      <h2 className="app-card-title">Mandates for this agent</h2>
      <div className="app-authority-selector-list">
        {items.map((item) => (
          <button
            key={item.mandate.id.toString()}
            type="button"
            className={`app-authority-selector-item${
              item.mandate.id === selectedId ? " active" : ""
            }`}
            aria-pressed={item.mandate.id === selectedId}
            onClick={() => onSelect(item.mandate.id)}
          >
            <span className="app-authority-selector-heading">
              <span>Mandate #{item.mandate.id.toString()}</span>
              <span className={`app-tag ${statusClass(item.lineageStatus)}`}>
                {item.lineageStatus}
              </span>
            </span>
            <span className="app-authority-selector-detail">
              {truncateAddress(item.mandate.vault)} · depth{" "}
              {item.mandate.delegationDepth}
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}

function LineageTree({ selected }: { selected: AuthorityMandate }) {
  return (
    <section className="app-card">
      <div className="app-authority-section-heading">
        <div>
          <h2 className="app-card-title">Delegation lineage</h2>
          <p>Authority narrows from the root Mandate to the selected agent.</p>
        </div>
      </div>
      <div className="app-authority-lineage">
        {selected.lineage.map((mandate, index) => (
          <div
            key={mandate.id.toString()}
            className={`app-authority-lineage-node${
              mandate.id === selected.mandate.id ? " current" : ""
            }`}
          >
            <div className="app-authority-lineage-heading">
              <span>
                Mandate #{mandate.id.toString()} · depth{" "}
                {mandate.delegationDepth}
              </span>
              <span
                className={`app-tag ${
                  mandate.status === 0
                    ? "app-tag-active"
                    : mandate.status === 1
                      ? "app-tag-paused"
                      : "app-tag-revoked"
                }`}
              >
                {mandate.status === 0
                  ? "Active record"
                  : mandate.status === 1
                    ? "Paused record"
                    : "Revoked record"}
              </span>
            </div>
            <div className="app-authority-lineage-agent">
              Agent{" "}
              <CopyAddress
                address={mandate.agent}
                label="Lineage agent address"
              />
            </div>
            <div className="app-authority-lineage-summary">
              {nativeLimit(mandate.rules.minNativeAmount)} floor ·{" "}
              {nativeLimit(mandate.rules.maxNativeAmount, true)} cap ·{" "}
              {mandate.rules.canDelegate
                ? "delegation allowed"
                : "delegation disabled"}
            </div>
            {index < selected.lineage.length - 1 && (
              <span
                className="app-authority-lineage-connector"
                aria-hidden="true"
              />
            )}
          </div>
        ))}
      </div>
    </section>
  );
}

export default function AppAuthority() {
  const [addressInput, setAddressInput] = useState<string>(demoAgent);
  const [lookupAddress, setLookupAddress] = useState<Address | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<bigint | null>(null);
  const { mandates, isLoading, error, refetch } = useAgentAuthority({
    agent: lookupAddress,
  });
  const hasLookup = lookupAddress !== null;

  const selected =
    mandates.find((item) => item.mandate.id === selectedId) ?? null;
  const selectedMandate = selected ?? mandates[0] ?? null;
  const activeCount = mandates.filter((item) => item.lineageActive).length;

  function handleLookup(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLookupError(null);
    if (!isAddress(addressInput) || /^0x0{40}$/i.test(addressInput)) {
      setLookupAddress(null);
      setSelectedId(null);
      setLookupError("Agent address must be a valid non-zero address.");
      return;
    }
    setSelectedId(null);
    setLookupAddress(addressInput as Address);
  }

  return (
    <>
      <div className="app-page-header">
        <h1>Authority</h1>
        <p>
          Inspect what an agent can do under each Mandate, including inherited
          limits, Preflight, and delegation lineage.
        </p>
      </div>

      <form className="app-card app-authority-lookup" onSubmit={handleLookup}>
        <div className="app-authority-section-heading">
          <div>
            <h2 className="app-card-title">Look up agent authority</h2>
          </div>
        </div>
        <div className="app-form-group">
          <label className="app-form-label" htmlFor="authority-address">
            Agent address
          </label>
          <div className="app-authority-input-row">
            <input
              id="authority-address"
              className="app-form-input"
              placeholder="0x..."
              value={addressInput}
              onChange={(event) => setAddressInput(event.target.value)}
            />
            <button type="submit" className="app-btn app-btn-primary">
              Look up
            </button>
          </div>
          <p className="app-form-hint">
            Demo agent pre-filled. Change the address to inspect another agent.
          </p>
          {lookupError && (
            <p className="app-alert app-alert-error" role="alert">
              {lookupError}
            </p>
          )}
        </div>
      </form>

      {hasLookup && isLoading && (
        <div className="app-empty app-card">
          <h2>Loading authority…</h2>
          <p>Reading the agent&apos;s Mandates and effective rules.</p>
        </div>
      )}

      {hasLookup && !isLoading && error && (
        <div className="app-alert app-alert-error" role="alert">
          {error}{" "}
          <button
            type="button"
            className="app-inline-action"
            onClick={() => void refetch()}
          >
            Try again
          </button>
        </div>
      )}

      {hasLookup && !isLoading && !error && mandates.length === 0 && (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>No Mandates found</h2>
          <p>This agent has no indexed Mandates on X Layer Testnet.</p>
        </div>
      )}

      {hasLookup && !isLoading && !error && selectedMandate && (
        <>
          <div className="app-stats app-authority-stats">
            <div className="app-stat">
              <div className="app-stat-label">Active authority</div>
              <div className="app-stat-value">{activeCount}</div>
            </div>
            <div className="app-stat">
              <div className="app-stat-label">Mandates inspected</div>
              <div className="app-stat-value">{mandates.length}</div>
            </div>
          </div>

          <div className="app-authority-layout">
            <MandateSelector
              items={mandates}
              selectedId={selectedMandate.mandate.id}
              onSelect={setSelectedId}
            />

            <div className="app-authority-main">
              <section className="app-card">
                <div className="app-authority-section-heading">
                  <div>
                    <h2 className="app-card-title">Effective authority</h2>
                    <p>
                      Mandate #{selectedMandate.mandate.id.toString()} · Vault{" "}
                      <CopyAddress
                        address={selectedMandate.mandate.vault}
                        label="Authority Vault address"
                      />
                    </p>
                  </div>
                  <span
                    className={`app-tag ${statusClass(selectedMandate.lineageStatus)}`}
                  >
                    {selectedMandate.lineageStatus}
                  </span>
                </div>

                {!selectedMandate.lineageActive && (
                  <p
                    className="app-alert app-alert-warning app-authority-state-alert"
                    role="status"
                  >
                    This lineage is not currently usable. The stored rules
                    remain visible for historical inspection.
                  </p>
                )}

                <h3 className="app-authority-subheading">
                  {selectedMandate.lineageActive
                    ? "Effective limits"
                    : "Stored Mandate limits"}
                </h3>
                <AuthorityRules
                  rules={
                    selectedMandate.effectiveRules ??
                    selectedMandate.mandate.rules
                  }
                />
                <div className="app-authority-validity">
                  <span>Validity</span>
                  <strong>
                    {validityLabel(
                      selectedMandate.effectiveValidAfter,
                      selectedMandate.effectiveValidUntil,
                    )}
                  </strong>
                </div>
              </section>

              <section className="app-card">
                <div className="app-authority-section-heading">
                  <div>
                    <h2 className="app-card-title">Preflight</h2>
                    <p>
                      Reserve floors applied before an Action Plan can execute.
                    </p>
                  </div>
                </div>
                <PreflightRules
                  rules={
                    selectedMandate.effectivePreflightRules ??
                    selectedMandate.mandate.preflightRules
                  }
                />
              </section>

              <LineageTree selected={selectedMandate} />
            </div>
          </div>
        </>
      )}
    </>
  );
}
