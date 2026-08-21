"use client";

import { useCallback, useState } from "react";
import { useConnection } from "wagmi";
import type { Address } from "viem";
import { AppModal } from "@/components/app/app-modal";
import { CopyAddress } from "@/components/app/copy-address";
import GrantlineMark from "@/components/grantline-mark";
import { TransactionStatus } from "@/components/app/transaction-status";
import { addresses, demoAgent, grantlineAbi } from "@/lib/contracts";
import {
  formatDate,
  formatError,
  formatNative,
  parseAddress,
  parseDateInput,
  parseOptionalNativeAmount,
} from "@/lib/app-utils";
import { useAppTransaction } from "@/lib/use-app-transaction";
import {
  getMandateStatusLabel,
  type MandateData,
  useMandates,
} from "@/lib/use-mandates";
import { useVaults } from "@/lib/use-vaults";

function statusClass(status: number): string {
  if (status === 0) return "app-tag-active";
  if (status === 1) return "app-tag-paused";
  return "app-tag-revoked";
}

function limitLabel(value: bigint, suffix = " OKB"): string {
  return value > 0n ? `${formatNative(value)}${suffix}` : "None";
}

function MandateCard({
  mandate,
  onRefetch,
  onRevoke,
}: {
  mandate: MandateData;
  onRefetch: () => Promise<unknown>;
  onRevoke: (mandate: MandateData) => void;
}) {
  const transaction = useAppTransaction();
  const [actionError, setActionError] = useState<string | null>(null);
  const hasActions = mandate.status !== 2;

  const handlePauseToggle = useCallback(async () => {
    setActionError(null);

    try {
      await transaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: mandate.status === 0 ? "pauseMandate" : "unpauseMandate",
        args: [mandate.id],
      });
      await onRefetch();
    } catch (error) {
      setActionError(formatError(error));
    }
  }, [mandate.id, mandate.status, onRefetch, transaction]);

  return (
    <article className="app-card app-mandate-card">
      <div className="app-card-heading">
        <div>
          <span className="app-eyebrow">Mandate #{mandate.id.toString()}</span>
          <CopyAddress address={mandate.vault} label="Vault address" />
        </div>
        <span className={`app-tag ${statusClass(mandate.status)}`}>
          {getMandateStatusLabel(mandate.status)}
        </span>
      </div>

      <div className="app-address-row">
        <span className="app-detail-label">Agent</span>
        <CopyAddress address={mandate.agent} label="Agent address" />
      </div>

      <dl className="app-detail-grid">
        <div>
          <dt>Native amount floor</dt>
          <dd>{limitLabel(mandate.rules.minNativeAmount)}</dd>
        </div>
        <div>
          <dt>Native amount cap</dt>
          <dd>{limitLabel(mandate.rules.maxNativeAmount)}</dd>
        </div>
        <div>
          <dt>Vault reserve floor</dt>
          <dd>{limitLabel(mandate.preflightRules.minNativeBalance)}</dd>
        </div>
        <div>
          <dt>Delegation</dt>
          <dd>{mandate.rules.canDelegate ? "Allowed" : "Disabled"}</dd>
        </div>
      </dl>

      <div
        className={`app-mandate-validity${
          hasActions ? "" : " app-mandate-validity-compact"
        }`}
      >
        <span className="app-detail-label">Validity</span>
        <span>
          {mandate.validAfter === 0n && mandate.validUntil === 0n
            ? "Any time"
            : `${formatDate(mandate.validAfter)} – ${formatDate(mandate.validUntil)}`}
        </span>
      </div>

      {hasActions && (
        <div className="app-card-actions">
          {(mandate.status === 0 || mandate.status === 1) && (
            <button
              type="button"
              className="app-btn app-btn-quiet"
              onClick={handlePauseToggle}
              disabled={transaction.isPending}
            >
              {transaction.isPending
                ? "Confirming…"
                : mandate.status === 0
                  ? "Pause"
                  : "Unpause"}
            </button>
          )}
          <button
            type="button"
            className="app-btn app-btn-danger"
            onClick={() => onRevoke(mandate)}
            disabled={transaction.isPending}
          >
            Revoke
          </button>
        </div>
      )}

      <TransactionStatus
        error={actionError ?? transaction.error}
        isPending={transaction.isPending}
        message="Confirm the Mandate change in your wallet."
      />
    </article>
  );
}

function emptyRules() {
  return {
    canDelegate: false,
    minNativeAmount: 0n,
    maxNativeAmount: 0n,
    escalateNativeAmount: false,
    minNativeUsd: 0n,
    maxNativeUsd: 0n,
    escalateNativeUsd: false,
  };
}

function emptyPreflightRules() {
  return {
    minNativeBalance: 0n,
    escalateNativeBalance: false,
    minNativeUsdBalance: 0n,
    escalateNativeUsdBalance: false,
  };
}

export default function MandatesPage() {
  const { address, isConnected } = useConnection();
  const { mandates, isLoading, error, refetch } = useMandates();
  const { vaults, error: vaultError } = useVaults();
  const createTransaction = useAppTransaction();
  const revokeTransaction = useAppTransaction();

  const [showCreate, setShowCreate] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<MandateData | null>(null);
  const [createVault, setCreateVault] = useState<Address | "">("");
  const [createAgent, setCreateAgent] = useState<string>(demoAgent);
  const [createMinNative, setCreateMinNative] = useState("");
  const [createMaxNative, setCreateMaxNative] = useState("");
  const [createEscalateNative, setCreateEscalateNative] = useState(false);
  const [createCanDelegate, setCreateCanDelegate] = useState(false);
  const [createMinBalance, setCreateMinBalance] = useState("");
  const [createEscalateBalance, setCreateEscalateBalance] = useState(false);
  const [createValidAfter, setCreateValidAfter] = useState("");
  const [createValidUntil, setCreateValidUntil] = useState("");
  const [createError, setCreateError] = useState<string | null>(null);
  const [revokeError, setRevokeError] = useState<string | null>(null);

  const connectedVaults = vaults
    .filter(
      (vault) =>
        vault.controller.toLowerCase() === address?.toLowerCase() &&
        !vault.paused,
    )
    .sort((a, b) => b.index - a.index);
  const selectedCreateVault = createVault || connectedVaults[0]?.address || "";

  const resetCreateForm = useCallback(() => {
    setCreateVault("");
    setCreateAgent(demoAgent);
    setCreateMinNative("");
    setCreateMaxNative("");
    setCreateEscalateNative(false);
    setCreateCanDelegate(false);
    setCreateMinBalance("");
    setCreateEscalateBalance(false);
    setCreateValidAfter("");
    setCreateValidUntil("");
    setCreateError(null);
  }, []);

  const closeCreate = useCallback(() => {
    if (createTransaction.isPending) return;
    setShowCreate(false);
    resetCreateForm();
  }, [createTransaction.isPending, resetCreateForm]);

  const closeRevoke = useCallback(() => {
    if (revokeTransaction.isPending) return;
    setRevokeTarget(null);
    setRevokeError(null);
  }, [revokeTransaction.isPending]);

  async function handleCreate() {
    setCreateError(null);

    try {
      if (!selectedCreateVault)
        throw new Error("Select an active Vault first.");
      const agent = parseAddress(createAgent, "Agent address");
      const minNativeAmount = parseOptionalNativeAmount(createMinNative);
      const maxNativeAmount = parseOptionalNativeAmount(createMaxNative);
      const minNativeBalance = parseOptionalNativeAmount(createMinBalance);
      const validAfter = parseDateInput(createValidAfter, "Valid after");
      const validUntil = parseDateInput(createValidUntil, "Valid until");

      if (
        minNativeAmount > 0n &&
        maxNativeAmount > 0n &&
        minNativeAmount > maxNativeAmount
      ) {
        throw new Error("The native amount floor cannot exceed the cap.");
      }
      if (validAfter > 0n && validUntil > 0n && validUntil < validAfter) {
        throw new Error("Valid until must be after valid after.");
      }

      await createTransaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "createMandate",
        args: [
          selectedCreateVault as Address,
          agent,
          {
            ...emptyRules(),
            canDelegate: createCanDelegate,
            minNativeAmount,
            maxNativeAmount,
            escalateNativeAmount: createEscalateNative,
          },
          {
            ...emptyPreflightRules(),
            minNativeBalance,
            escalateNativeBalance: createEscalateBalance,
          },
          validAfter,
          validUntil,
        ],
      });
      setShowCreate(false);
      resetCreateForm();
      await refetch();
    } catch (error) {
      setCreateError(formatError(error));
    }
  }

  const handleRevoke = useCallback(async () => {
    if (!revokeTarget) return;
    setRevokeError(null);

    try {
      await revokeTransaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "revokeMandate",
        args: [revokeTarget.id],
      });
      closeRevoke();
      await refetch();
    } catch (error) {
      setRevokeError(formatError(error));
    }
  }, [closeRevoke, refetch, revokeTarget, revokeTransaction]);

  if (!isConnected) {
    return (
      <>
        <div className="app-page-header">
          <h1>Mandates</h1>
          <p>
            Create and manage Mandates that give agents bounded authority over
            your Vaults.
          </p>
        </div>
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>Connect your wallet</h2>
          <p>Connect your wallet to manage Mandates for your Vaults.</p>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="app-page-header app-page-header-row">
        <div>
          <h1>Mandates</h1>
          <p>
            {mandates.length} Mandate{mandates.length === 1 ? "" : "s"} managed
            by your wallet.
          </p>
        </div>
        <button
          type="button"
          className="app-btn app-btn-primary"
          onClick={() => {
            setCreateError(null);
            setShowCreate(true);
          }}
          disabled={connectedVaults.length === 0 || createTransaction.isPending}
        >
          Create Mandate
        </button>
      </div>

      {error && (
        <div className="app-alert app-alert-error" role="alert">
          {error}
        </div>
      )}
      {!error && vaultError && (
        <div className="app-alert app-alert-error" role="alert">
          {vaultError}
        </div>
      )}

      {isLoading && (
        <div className="app-empty app-card">
          <h2>Loading Mandates…</h2>
          <p>Reading your Mandates from X Layer Testnet.</p>
        </div>
      )}

      {!isLoading && !error && mandates.length === 0 && (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>No Mandates yet</h2>
          <p>
            Create a Mandate to give an agent bounded authority over one of your
            Vaults.
          </p>
          {connectedVaults.length === 0 ? (
            <p className="app-form-hint">
              Create and fund an active Vault before creating a Mandate.
            </p>
          ) : (
            <button
              type="button"
              className="app-btn app-btn-primary"
              onClick={() => setShowCreate(true)}
            >
              Create your first Mandate
            </button>
          )}
        </div>
      )}

      {!isLoading && !error && mandates.length > 0 && (
        <div className="app-card-grid">
          {[...mandates]
            .sort((a, b) => {
              if (a.status !== b.status) return a.status - b.status;
              if (a.id === b.id) return 0;
              return a.id > b.id ? -1 : 1;
            })
            .map((mandate) => (
              <MandateCard
                key={mandate.id.toString()}
                mandate={mandate}
                onRefetch={refetch}
                onRevoke={(target) => {
                  setRevokeError(null);
                  setRevokeTarget(target);
                }}
              />
            ))}
        </div>
      )}

      {showCreate && (
        <AppModal
          title="Create Mandate"
          description="Authorise an agent to act within a bounded Vault policy."
          onClose={closeCreate}
          closeDisabled={createTransaction.isPending}
        >
          <form
            className="app-modal-form"
            onSubmit={(event) => {
              event.preventDefault();
              void handleCreate();
            }}
          >
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="mandate-vault">
                Vault
              </label>
              <select
                id="mandate-vault"
                className="app-form-input"
                value={selectedCreateVault}
                onChange={(event) =>
                  setCreateVault(event.target.value as Address)
                }
              >
                {connectedVaults.map((vault) => (
                  <option key={vault.address} value={vault.address}>
                    Vault #{vault.index} · {formatNative(vault.nativeBalance)}{" "}
                    OKB
                  </option>
                ))}
              </select>
            </div>

            <div className="app-form-group">
              <label className="app-form-label" htmlFor="mandate-agent">
                Agent address
              </label>
              <input
                id="mandate-agent"
                className="app-form-input"
                type="text"
                inputMode="text"
                autoComplete="off"
                placeholder="0x…"
                value={createAgent}
                onChange={(event) => setCreateAgent(event.target.value)}
              />
              <p className="app-form-hint">
                The demo agent is pre-filled for the testnet walkthrough, but
                you can replace it with any agent address you control.
              </p>
            </div>

            <div className="app-form-grid">
              <div className="app-form-group">
                <label className="app-form-label" htmlFor="mandate-min-native">
                  Native amount floor (OKB)
                </label>
                <input
                  id="mandate-min-native"
                  className="app-form-input"
                  type="text"
                  inputMode="decimal"
                  placeholder="No floor"
                  value={createMinNative}
                  onChange={(event) => setCreateMinNative(event.target.value)}
                />
              </div>
              <div className="app-form-group">
                <label className="app-form-label" htmlFor="mandate-max-native">
                  Native amount cap (OKB)
                </label>
                <input
                  id="mandate-max-native"
                  className="app-form-input"
                  type="text"
                  inputMode="decimal"
                  placeholder="No cap"
                  value={createMaxNative}
                  onChange={(event) => setCreateMaxNative(event.target.value)}
                />
              </div>
            </div>

            <label className="app-checkbox">
              <input
                type="checkbox"
                checked={createEscalateNative}
                onChange={(event) =>
                  setCreateEscalateNative(event.target.checked)
                }
              />
              Escalate native amount overruns when supported.
            </label>

            <label className="app-checkbox">
              <input
                type="checkbox"
                checked={createCanDelegate}
                onChange={(event) => setCreateCanDelegate(event.target.checked)}
              />
              Allow the agent to delegate narrower authority.
            </label>

            <div className="app-form-group">
              <label className="app-form-label" htmlFor="mandate-min-balance">
                Minimum Vault reserve (OKB)
              </label>
              <input
                id="mandate-min-balance"
                className="app-form-input"
                type="text"
                inputMode="decimal"
                placeholder="No reserve floor"
                value={createMinBalance}
                onChange={(event) => setCreateMinBalance(event.target.value)}
              />
            </div>

            <label className="app-checkbox">
              <input
                type="checkbox"
                checked={createEscalateBalance}
                onChange={(event) =>
                  setCreateEscalateBalance(event.target.checked)
                }
              />
              Escalate reserve breaches when supported.
            </label>

            <div className="app-form-grid">
              <div className="app-form-group">
                <label className="app-form-label" htmlFor="mandate-valid-after">
                  Valid after (optional)
                </label>
                <input
                  id="mandate-valid-after"
                  className="app-form-input"
                  type="datetime-local"
                  value={createValidAfter}
                  onChange={(event) => setCreateValidAfter(event.target.value)}
                />
              </div>
              <div className="app-form-group">
                <label className="app-form-label" htmlFor="mandate-valid-until">
                  Valid until (optional)
                </label>
                <input
                  id="mandate-valid-until"
                  className="app-form-input"
                  type="datetime-local"
                  value={createValidUntil}
                  onChange={(event) => setCreateValidUntil(event.target.value)}
                />
              </div>
            </div>

            <TransactionStatus
              error={createError ?? createTransaction.error}
              isPending={createTransaction.isPending}
              message="Confirm the Mandate creation in your wallet."
            />
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={closeCreate}
                disabled={createTransaction.isPending}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="app-btn app-btn-primary"
                disabled={createTransaction.isPending || !selectedCreateVault}
              >
                {createTransaction.isPending ? "Confirming…" : "Create Mandate"}
              </button>
            </div>
          </form>
        </AppModal>
      )}

      {revokeTarget && (
        <AppModal
          title={`Revoke Mandate #${revokeTarget.id.toString()}`}
          description="This permanently removes the Mandate’s authority and affects its delegated lineage."
          onClose={closeRevoke}
          closeDisabled={revokeTransaction.isPending}
        >
          <div className="app-modal-form app-revoke-form">
            <p className="app-revoke-warning">
              The agent will no longer be able to use this Mandate, and future
              actions under its lineage will fail.
            </p>
            <TransactionStatus
              error={revokeError ?? revokeTransaction.error}
              isPending={revokeTransaction.isPending}
              message="Confirm the revocation in your wallet."
            />
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={closeRevoke}
                disabled={revokeTransaction.isPending}
              >
                Cancel
              </button>
              <button
                type="button"
                className="app-btn app-btn-danger"
                onClick={() => void handleRevoke()}
                disabled={revokeTransaction.isPending}
              >
                {revokeTransaction.isPending ? "Confirming…" : "Revoke Mandate"}
              </button>
            </div>
          </div>
        </AppModal>
      )}
    </>
  );
}
