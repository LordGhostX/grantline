"use client";

import { useState, useCallback } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSwitchChain,
} from "wagmi";
import { parseEther } from "viem";
import type { Hex } from "viem";
import { addresses, grantlineAbi, chainId, demoAgent } from "@/lib/contracts";
import {
  type MandateData,
  formatOkb,
  getMandateStatusLabel,
  truncateHex,
  useMandates,
} from "@/lib/use-mandates";
import { useVaults } from "@/lib/use-vaults";

function formatError(err: unknown): string {
  if (!err) return "";
  if (typeof err === "object" && err !== null && "shortMessage" in err) {
    return String((err as { shortMessage: string }).shortMessage);
  }
  if (err instanceof Error) return err.message;
  return String(err);
}

function MandateCard({
  mandate,
  onRefetch,
  onRevoke,
  switchChain,
}: {
  mandate: MandateData;
  onRefetch: () => void;
  onRevoke: (m: MandateData) => void;
  switchChain: ReturnType<typeof useSwitchChain>["switchChain"];
}) {
  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: txLoading } = useWaitForTransactionReceipt({
    hash: txHash,
  });
  const [pauseError, setPauseError] = useState<string | null>(null);

  const [vaultCopied, setVaultCopied] = useState(false);
  const [agentCopied, setAgentCopied] = useState(false);

  function copyToClipboard(text: string, which: "vault" | "agent") {
    navigator.clipboard.writeText(text);
    if (which === "vault") {
      setVaultCopied(true);
      setTimeout(() => setVaultCopied(false), 1500);
    } else {
      setAgentCopied(true);
      setTimeout(() => setAgentCopied(false), 1500);
    }
  }

  const handlePauseToggle = useCallback(async () => {
    setPauseError(null);
    try {
      await switchChain({ chainId });
      const fn = mandate.status === 0 ? "pauseMandate" : "unpauseMandate";
      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: fn,
          args: [mandate.id],
          chainId,
        },
        {
          onSuccess: () => {
            setTimeout(() => onRefetch(), 1500);
          },
          onError: (err) => {
            setPauseError(formatError(err));
          },
        },
      );
    } catch (err) {
      setPauseError(formatError(err));
    }
  }, [mandate.id, mandate.status, writeContract, onRefetch, switchChain]);

  return (
    <div className="app-card">
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          marginBottom: 16,
        }}
      >
        <div>
          <div style={{ fontSize: 13, color: "#9a9896", marginBottom: 4 }}>
            Mandate #{mandate.id.toString()}
          </div>
          <div
            className="app-code"
            style={{ cursor: "pointer" }}
            title={mandate.vault}
            onClick={() => copyToClipboard(mandate.vault, "vault")}
          >
            {vaultCopied ? "Copied!" : truncateHex(mandate.vault)}
          </div>
        </div>
        <span
          className={
            mandate.status === 0
              ? "app-tag app-tag-active"
              : mandate.status === 1
                ? "app-tag app-tag-paused"
                : "app-tag app-tag-revoked"
          }
        >
          {getMandateStatusLabel(mandate.status)}
        </span>
      </div>

      <div style={{ marginBottom: 16 }}>
        <div style={{ fontSize: 13, color: "#9a9896", marginBottom: 4 }}>
          Agent
        </div>
        <div
          className="app-code"
          style={{ cursor: "pointer", width: "fit-content" }}
          title={mandate.agent}
          onClick={() => copyToClipboard(mandate.agent, "agent")}
        >
          {agentCopied ? "Copied!" : truncateHex(mandate.agent)}
        </div>
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 12,
          marginBottom: 16,
        }}
      >
        <div>
          <div style={{ fontSize: 13, color: "#9a9896", marginBottom: 2 }}>
            Max native
          </div>
          <div style={{ fontSize: 14 }}>
            {mandate.rules.maxNativeAmount > 0n
              ? `${formatOkb(mandate.rules.maxNativeAmount)} OKB`
              : "No cap"}
          </div>
        </div>
        <div>
          <div style={{ fontSize: 13, color: "#9a9896", marginBottom: 2 }}>
            Delegate
          </div>
          <div style={{ fontSize: 14 }}>
            {mandate.rules.canDelegate ? "Allowed" : "Denied"}
          </div>
        </div>
      </div>

      {(mandate.validAfter > 0n || mandate.validUntil > 0n) && (
        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 13, color: "#9a9896", marginBottom: 2 }}>
            Valid
          </div>
          <div style={{ fontSize: 14 }}>
            {mandate.validAfter > 0n
              ? new Date(Number(mandate.validAfter) * 1000).toLocaleDateString()
              : "Any"}
            {" \u2013 "}
            {mandate.validUntil > 0n
              ? new Date(Number(mandate.validUntil) * 1000).toLocaleDateString()
              : "Any"}
          </div>
        </div>
      )}

      {pauseError && (
        <div
          style={{
            marginBottom: 8,
            fontSize: 12,
            color: "var(--deny, #d97878)",
          }}
        >
          {pauseError}
        </div>
      )}

      <div style={{ display: "flex", gap: 8 }}>
        {(mandate.status === 0 || mandate.status === 1) && (
          <button
            type="button"
            className="app-btn app-btn-quiet"
            style={{ flex: 1 }}
            disabled={isPending || txLoading}
            onClick={handlePauseToggle}
          >
            {isPending || txLoading
              ? "Waiting\u2026"
              : mandate.status === 0
                ? "Pause"
                : "Unpause"}
          </button>
        )}
        {mandate.status !== 2 && (
          <button
            type="button"
            className="app-btn app-btn-quiet"
            style={{
              flex: 1,
              color: "var(--deny, #d97878)",
              borderColor: "rgba(217, 119, 87, 0.3)",
            }}
            onClick={() => onRevoke(mandate)}
          >
            Revoke
          </button>
        )}
      </div>
    </div>
  );
}

export default function MandatesPage() {
  const { address, isConnected } = useAccount();
  const { mandates, isLoading, error, refetch } = useMandates();
  const { vaults } = useVaults();
  const { writeContract } = useWriteContract();
  const { switchChain } = useSwitchChain();

  const [showCreate, setShowCreate] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<MandateData | null>(null);

  const [createVault, setCreateVault] = useState<Hex>("0x");
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
      (v) => v.controller.toLowerCase() === address?.toLowerCase() && !v.paused,
    )
    .sort((a, b) => b.index - a.index);

  const selectedCreateVault =
    createVault !== "0x"
      ? createVault
      : connectedVaults.length > 0
        ? connectedVaults[0].address
        : "0x";

  async function handleCreate() {
    if (!createAgent || selectedCreateVault === "0x") return;
    setCreateError(null);
    try {
      await switchChain({ chainId });
      const minNative = createMinNative ? parseEther(createMinNative) : 0n;
      const maxNative = createMaxNative ? parseEther(createMaxNative) : 0n;
      const minBal = createMinBalance ? parseEther(createMinBalance) : 0n;
      const after = createValidAfter
        ? BigInt(Math.floor(new Date(createValidAfter).getTime() / 1000))
        : 0n;
      const until = createValidUntil
        ? BigInt(Math.floor(new Date(createValidUntil).getTime() / 1000))
        : 0n;

      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "createMandate",
          args: [
            selectedCreateVault,
            createAgent as Hex,
            {
              canDelegate: createCanDelegate,
              minNativeAmount: minNative,
              maxNativeAmount: maxNative,
              escalateNativeAmount: createEscalateNative,
              minNativeUsd: 0n,
              maxNativeUsd: 0n,
              escalateNativeUsd: false,
            },
            {
              minNativeBalance: minBal,
              escalateNativeBalance: createEscalateBalance,
              minNativeUsdBalance: 0n,
              escalateNativeUsdBalance: false,
            },
            after,
            until,
          ],
          chainId,
        },
        {
          onSuccess: () => {
            setShowCreate(false);
            setCreateAgent(demoAgent);
            setCreateMinNative("");
            setCreateMaxNative("");
            setCreateEscalateNative(false);
            setCreateCanDelegate(false);
            setCreateMinBalance("");
            setCreateEscalateBalance(false);
            setCreateValidAfter("");
            setCreateValidUntil("");
            setTimeout(() => refetch(), 1500);
          },
          onError: (err) => {
            setCreateError(formatError(err));
          },
        },
      );
    } catch (err) {
      setCreateError(formatError(err));
    }
  }

  const handleRevoke = useCallback(async () => {
    if (!revokeTarget) return;
    setRevokeError(null);
    try {
      await switchChain({ chainId });
      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "revokeMandate",
          args: [revokeTarget.id],
          chainId,
        },
        {
          onSuccess: () => {
            setRevokeTarget(null);
            setTimeout(() => refetch(), 1500);
          },
          onError: (err) => {
            setRevokeError(formatError(err));
          },
        },
      );
    } catch (err) {
      setRevokeError(formatError(err));
    }
  }, [revokeTarget, writeContract, refetch, switchChain]);

  if (!isConnected) {
    return (
      <div className="app-empty">
        <div className="app-empty-icon">&#9878;</div>
        <h3>Connect your wallet</h3>
        <p>Connect your wallet to manage mandates.</p>
      </div>
    );
  }

  return (
    <>
      <div className="app-page-header">
        <h1>Mandates</h1>
        <p>
          {mandates.length} mandate{mandates.length !== 1 ? "s" : ""} assigned
          to you
        </p>
      </div>

      <div style={{ marginBottom: 24 }}>
        <button
          type="button"
          className="app-btn app-btn-primary"
          onClick={() => setShowCreate(true)}
          disabled={connectedVaults.length === 0}
        >
          Create Mandate
        </button>
      </div>

      {error && (
        <div
          style={{
            padding: "12px 16px",
            marginBottom: 16,
            borderRadius: "var(--radius, 6px)",
            background: "rgba(217, 119, 87, 0.1)",
            border: "1px solid rgba(217, 119, 87, 0.2)",
            fontSize: 14,
            color: "var(--deny, #d97757)",
          }}
        >
          {error}
        </div>
      )}

      {isLoading && (
        <div className="app-empty">
          <h3>Loading mandates&#8230;</h3>
        </div>
      )}

      {!isLoading && mandates.length === 0 && !error && (
        <div className="app-empty">
          <div className="app-empty-icon">&#9878;</div>
          <h3>No mandates assigned</h3>
          <p>No mandates have been assigned to your wallet yet.</p>
          {connectedVaults.length === 0 && (
            <p style={{ marginTop: 8, fontSize: 13, color: "#5a5856" }}>
              You need at least one active vault to create a mandate.
            </p>
          )}
        </div>
      )}

      {!isLoading && mandates.length > 0 && (
        <div className="app-card-grid">
          {[...mandates]
            .sort((a, b) => Number(b.id) - Number(a.id))
            .map((m) => (
              <MandateCard
                key={m.id.toString()}
                mandate={m}
                onRefetch={refetch}
                onRevoke={setRevokeTarget}
                switchChain={switchChain}
              />
            ))}
        </div>
      )}

      {showCreate && (
        <div
          className="app-modal-backdrop"
          onClick={() => setShowCreate(false)}
        >
          <div className="app-modal" onClick={(e) => e.stopPropagation()}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "flex-start",
                marginBottom: 8,
              }}
            >
              <h3 style={{ margin: 0, fontSize: 16 }}>Create Mandate</h3>
              <button
                type="button"
                className="app-modal-close"
                onClick={() => setShowCreate(false)}
              >
                &times;
              </button>
            </div>
            <p style={{ margin: 0, fontSize: 14, color: "#9a9896" }}>
              Authorise an agent to act under the chosen vault.
            </p>

            <div className="app-form-group" style={{ marginTop: 20 }}>
              <label className="app-form-label" htmlFor="mandate-vault">
                Vault
              </label>
              <select
                id="mandate-vault"
                className="app-form-input"
                value={selectedCreateVault}
                onChange={(e) => setCreateVault(e.target.value as Hex)}
              >
                {connectedVaults.map((v) => (
                  <option key={v.address} value={v.address}>
                    #{v.index} &#8211; {truncateHex(v.address)} (
                    {formatOkb(v.nativeBalance)} OKB)
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
                placeholder="0x..."
                value={createAgent}
                onChange={(e) => setCreateAgent(e.target.value)}
              />
              <p style={{ margin: "4px 0 0", fontSize: 12, color: "#5a5856" }}>
                Demo agent pre-filled. Create a mandate for it, then head to
                Execute to test a full action plan.
              </p>
            </div>

            <div className="app-form-group">
              <label className="app-form-label" style={{ cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={createCanDelegate}
                  onChange={(e) => setCreateCanDelegate(e.target.checked)}
                  style={{ marginRight: 8 }}
                />
                Allow agent to delegate
              </label>
            </div>

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                gap: 12,
              }}
            >
              <div className="app-form-group">
                <label className="app-form-label" htmlFor="mandate-min-native">
                  Min native amount (OKB)
                </label>
                <input
                  id="mandate-min-native"
                  className="app-form-input"
                  type="number"
                  step="0.01"
                  placeholder="0 = no floor"
                  value={createMinNative}
                  onChange={(e) => setCreateMinNative(e.target.value)}
                />
              </div>
              <div className="app-form-group">
                <label className="app-form-label" htmlFor="mandate-max-native">
                  Max native amount (OKB)
                </label>
                <input
                  id="mandate-max-native"
                  className="app-form-input"
                  type="number"
                  step="0.01"
                  placeholder="0 = no cap"
                  value={createMaxNative}
                  onChange={(e) => setCreateMaxNative(e.target.value)}
                />
              </div>
            </div>

            <div className="app-form-group">
              <label className="app-form-label" style={{ cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={createEscalateNative}
                  onChange={(e) => setCreateEscalateNative(e.target.checked)}
                  style={{ marginRight: 8 }}
                />
                Escalate on native amount overrun
              </label>
            </div>

            <div className="app-form-group">
              <label className="app-form-label" htmlFor="mandate-min-balance">
                Min vault balance reserve (OKB)
              </label>
              <input
                id="mandate-min-balance"
                className="app-form-input"
                type="number"
                step="0.01"
                placeholder="0 = no floor"
                value={createMinBalance}
                onChange={(e) => setCreateMinBalance(e.target.value)}
              />
            </div>

            <div className="app-form-group">
              <label className="app-form-label" style={{ cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={createEscalateBalance}
                  onChange={(e) => setCreateEscalateBalance(e.target.checked)}
                  style={{ marginRight: 8 }}
                />
                Escalate on balance reserve breach
              </label>
            </div>

            <div className="app-form-group">
              <label className="app-form-label" htmlFor="mandate-valid-after">
                Valid after (optional)
              </label>
              <input
                id="mandate-valid-after"
                className="app-form-input"
                type="datetime-local"
                value={createValidAfter}
                onChange={(e) => setCreateValidAfter(e.target.value)}
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
                onChange={(e) => setCreateValidUntil(e.target.value)}
              />
            </div>

            {createError && (
              <div
                style={{
                  fontSize: 12,
                  color: "var(--deny, #d97878)",
                  marginBottom: 12,
                }}
              >
                {createError}
              </div>
            )}

            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={() => setShowCreate(false)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="app-btn app-btn-primary"
                onClick={handleCreate}
                disabled={!createAgent || selectedCreateVault === "0x"}
              >
                Create Mandate
              </button>
            </div>
          </div>
        </div>
      )}

      {revokeTarget && (
        <div
          className="app-modal-backdrop"
          onClick={() => setRevokeTarget(null)}
        >
          <div className="app-modal" onClick={(e) => e.stopPropagation()}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "flex-start",
                marginBottom: 8,
              }}
            >
              <h3 style={{ margin: 0, fontSize: 16 }}>
                Revoke Mandate #{revokeTarget.id.toString()}
              </h3>
              <button
                type="button"
                className="app-modal-close"
                onClick={() => setRevokeTarget(null)}
              >
                &times;
              </button>
            </div>
            <p style={{ margin: 0, fontSize: 14, color: "#9a9896" }}>
              This action is permanent. The agent will lose all authority under
              this mandate and any delegated child mandates will be revoked.
            </p>
            {revokeError && (
              <div
                style={{
                  marginTop: 12,
                  fontSize: 12,
                  color: "var(--deny, #d97878)",
                }}
              >
                {revokeError}
              </div>
            )}
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={() => setRevokeTarget(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="app-btn app-btn-primary"
                style={{ background: "var(--deny, #d97757)" }}
                onClick={handleRevoke}
              >
                Revoke Mandate
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
