"use client";

import { useEffect, useState } from "react";
import { encodeAbiParameters, zeroAddress } from "viem";
import { useConnection, useSignTypedData, useSwitchChain } from "wagmi";
import { TransactionStatus } from "@/components/app/transaction-status";
import GrantlineMark from "@/components/grantline-mark";
import { addresses, chainId, demoAgent, grantlineAbi } from "@/lib/contracts";
import {
  assertFutureTimestamp,
  parseAddress,
  parseNativeAmount,
} from "@/lib/app-utils";
import { useAppTransaction } from "@/lib/use-app-transaction";
import { getMandateStatusLabel, useMandates } from "@/lib/use-mandates";

type ActionTab = "transfer" | "swap";

const actionTypes = {
  Action: [
    { name: "actionType", type: "uint8" },
    { name: "version", type: "uint8" },
    { name: "parameters", type: "bytes" },
  ],
  ActionPlan: [
    { name: "mandateId", type: "uint256" },
    { name: "agent", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "actions", type: "Action[]" },
  ],
} as const;

function nextDemoNonce(previous = ""): string {
  const current = BigInt(Math.floor(Date.now() / 1000));
  if (!/^\d+$/.test(previous)) return current.toString();

  const previousNonce = BigInt(previous);
  return (current > previousNonce ? current : previousNonce + 1n).toString();
}

export default function AppExecute() {
  const { address, chainId: connectedChainId, isConnected } = useConnection();
  const {
    mandates,
    isLoading: mandatesLoading,
    error: mandatesError,
  } = useMandates({ scope: "all", enabled: isConnected });
  const signTypedData = useSignTypedData();
  const switchChain = useSwitchChain();
  const transaction = useAppTransaction();
  const [tab, setTab] = useState<ActionTab>("transfer");
  const [mandateId, setMandateId] = useState("");
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("0.001");
  const [nonce, setNonce] = useState("");
  const [deadline, setDeadline] = useState("");
  const [flowError, setFlowError] = useState<unknown>(null);
  const [transactionHash, setTransactionHash] = useState<string | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => setNonce(nextDemoNonce()), 0);
    return () => window.clearTimeout(timer);
  }, []);

  const activeMandates = mandates.filter((mandate) => mandate.status === 0);
  const selectedMandate =
    activeMandates.find((mandate) => mandate.id.toString() === mandateId) ??
    activeMandates[0];
  const mandatesReady = !mandatesLoading && !mandatesError;
  const signerMatches =
    Boolean(address && selectedMandate) &&
    address!.toLowerCase() === selectedMandate!.agent.toLowerCase();
  const isPending =
    signTypedData.isPending || switchChain.isPending || transaction.isPending;
  const error =
    flowError ?? signTypedData.error ?? switchChain.error ?? transaction.error;

  async function handleTransfer() {
    setFlowError(null);
    setTransactionHash(null);
    signTypedData.reset();
    switchChain.reset();

    try {
      if (!address) {
        throw new Error("Connect the agent wallet to sign this Action Plan.");
      }
      if (!selectedMandate) {
        throw new Error(
          "Create an active Mandate before executing an Action Plan.",
        );
      }
      if (selectedMandate.status !== 0) {
        throw new Error(
          `Mandate #${selectedMandate.id.toString()} is ${getMandateStatusLabel(selectedMandate.status).toLowerCase()}.`,
        );
      }
      if (!signerMatches) {
        throw new Error(
          `Connect the agent wallet ${selectedMandate.agent} to sign this Action Plan.`,
        );
      }

      const parsedRecipient = parseAddress(recipient, "Recipient");
      const parsedAmount = parseNativeAmount(amount, "Amount");
      const parsedNonce = nonce.trim();
      if (!/^\d+$/.test(parsedNonce)) {
        throw new Error("Nonce must be a whole number.");
      }
      const parsedDeadline = new Date(deadline).getTime();
      if (!deadline || !Number.isFinite(parsedDeadline)) {
        throw new Error("Deadline must be a valid date.");
      }
      const deadlineSeconds = BigInt(Math.floor(parsedDeadline / 1000));
      assertFutureTimestamp(deadlineSeconds, "Deadline");

      if (connectedChainId !== chainId) {
        await switchChain.mutateAsync({ chainId });
      }

      const parameters = encodeAbiParameters(
        [
          { name: "asset", type: "address" },
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
        ],
        [zeroAddress, parsedRecipient, parsedAmount],
      );
      const plan = {
        mandateId: selectedMandate.id,
        agent: selectedMandate.agent,
        nonce: BigInt(parsedNonce),
        deadline: deadlineSeconds,
        actions: [{ actionType: 0, version: 1, parameters }],
      } as const;

      const signature = await signTypedData.mutateAsync({
        domain: {
          name: "Grantline",
          version: "1",
          chainId,
          verifyingContract: addresses.grantline,
        },
        types: actionTypes,
        primaryType: "ActionPlan",
        message: plan,
      });

      const hash = await transaction.submit(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "execute",
          args: [plan, signature],
        },
        { skipChainSwitch: true },
      );
      setTransactionHash(hash);
      setNonce((currentNonce) => nextDemoNonce(currentNonce));
    } catch (submissionError) {
      setFlowError(submissionError);
    }
  }

  if (!isConnected) {
    return (
      <>
        <div className="app-page-header">
          <h1>Execute</h1>
          <p>
            Sign an Action Plan and submit it for Grantline&apos;s authority
            review.
          </p>
        </div>
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>Connect your wallet</h2>
          <p>Connect the agent wallet to sign and execute an Action Plan.</p>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="app-page-header">
        <h1>Execute</h1>
        <p>
          Sign an Action Plan and submit it for Grantline&apos;s authority
          review.
        </p>
      </div>

      <div
        className="app-tabs app-action-tabs"
        role="tablist"
        aria-label="Action type"
      >
        <button
          type="button"
          role="tab"
          aria-selected={tab === "transfer"}
          className={`app-tab${tab === "transfer" ? " active" : ""}`}
          onClick={() => setTab("transfer")}
        >
          TRANSFER
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === "swap"}
          className={`app-tab${tab === "swap" ? " active" : ""}`}
          onClick={() => setTab("swap")}
        >
          SWAP
        </button>
      </div>

      <div className="app-card">
        {tab === "transfer" ? (
          mandatesLoading ? (
            <div className="app-empty">
              <h2>Loading Mandates…</h2>
              <p>Reading your Mandates from X Layer Testnet.</p>
            </div>
          ) : (
            <>
              <h2 className="app-card-title">Transfer native token</h2>

              {!mandatesLoading && mandatesError && (
                <p className="app-alert app-alert-error" role="alert">
                  {mandatesError}
                </p>
              )}

              {mandatesReady && isConnected && mandates.length === 0 && (
                <p className="app-alert app-alert-warning" role="status">
                  Create a Mandate before signing an Action Plan.
                </p>
              )}

              {mandatesReady &&
                isConnected &&
                mandates.length > 0 &&
                activeMandates.length === 0 && (
                  <p className="app-alert app-alert-warning" role="status">
                    No active Mandates are available for signing an Action Plan.
                  </p>
                )}

              {mandatesReady &&
                isConnected &&
                selectedMandate &&
                !signerMatches && (
                  <>
                    <p className="app-alert app-alert-warning" role="status">
                      Connect the agent wallet for this Mandate before signing.
                      The current wallet is {address}.
                    </p>
                    <p className="app-execute-note" role="note">
                      Mandates created with the connected agent wallet can
                      proceed as-is; the demo requests the Action Plan signature
                      from that wallet.
                      <br />
                      <strong>Demo agent wallet: {demoAgent}</strong>
                    </p>
                  </>
                )}

              {mandatesReady && (
                <>
                  {selectedMandate && (
                    <div className="app-form-group">
                      <label
                        className="app-form-label"
                        htmlFor="transfer-mandate"
                      >
                        Mandate
                      </label>
                      <select
                        id="transfer-mandate"
                        className="app-form-input"
                        value={selectedMandate.id.toString()}
                        onChange={(event) => setMandateId(event.target.value)}
                      >
                        {activeMandates.map((mandate) => (
                          <option
                            key={mandate.id.toString()}
                            value={mandate.id.toString()}
                          >
                            Mandate #{mandate.id.toString()} ·{" "}
                            {getMandateStatusLabel(mandate.status)} ·{" "}
                            {mandate.agent}
                          </option>
                        ))}
                      </select>
                      <p className="app-form-hint">
                        Agent: {selectedMandate.agent} · Vault:{" "}
                        {selectedMandate.vault}
                      </p>
                    </div>
                  )}

                  <div className="app-form-group">
                    <label className="app-form-label" htmlFor="transfer-to">
                      Recipient
                    </label>
                    <input
                      id="transfer-to"
                      className="app-form-input"
                      placeholder="0x..."
                      value={recipient}
                      onChange={(event) => setRecipient(event.target.value)}
                    />
                  </div>

                  <div className="app-form-grid">
                    <div className="app-form-group">
                      <label
                        className="app-form-label"
                        htmlFor="transfer-amount"
                      >
                        Amount (OKB)
                      </label>
                      <input
                        id="transfer-amount"
                        className="app-form-input"
                        inputMode="decimal"
                        placeholder="0.001"
                        value={amount}
                        onChange={(event) => setAmount(event.target.value)}
                      />
                    </div>
                    <div className="app-form-group">
                      <label
                        className="app-form-label"
                        htmlFor="transfer-nonce"
                      >
                        Nonce
                      </label>
                      <input
                        id="transfer-nonce"
                        className="app-form-input"
                        inputMode="numeric"
                        placeholder="Generating…"
                        aria-describedby="transfer-nonce-hint"
                        value={nonce}
                        onChange={(event) => setNonce(event.target.value)}
                      />
                      <p id="transfer-nonce-hint" className="app-form-hint">
                        Generated from the current time and refreshed after each
                        successful execution. You can change it manually.
                      </p>
                    </div>
                  </div>

                  <div className="app-form-group">
                    <label
                      className="app-form-label"
                      htmlFor="transfer-deadline"
                    >
                      Deadline
                    </label>
                    <input
                      id="transfer-deadline"
                      className="app-form-input"
                      type="datetime-local"
                      value={deadline}
                      onChange={(event) => setDeadline(event.target.value)}
                    />
                    <p className="app-form-hint">
                      The Action Plan expires at this local time. Choose a
                      future time so the signed plan remains valid while it is
                      submitted.
                    </p>
                  </div>

                  <TransactionStatus
                    error={error}
                    isPending={isPending}
                    message={
                      switchChain.isPending
                        ? "Switch to X Layer Testnet in your wallet…"
                        : signTypedData.isPending
                          ? "Sign the Action Plan in your wallet…"
                          : "Confirm the execution transaction in your wallet…"
                    }
                  />

                  {transactionHash && (
                    <p className="app-alert app-alert-info" role="status">
                      Action Plan executed. Transaction:{" "}
                      <span className="app-code">{transactionHash}</span>
                    </p>
                  )}

                  <button
                    type="button"
                    className="app-btn app-btn-primary"
                    disabled={
                      isPending ||
                      !nonce.trim() ||
                      !selectedMandate ||
                      !signerMatches
                    }
                    onClick={() => void handleTransfer()}
                  >
                    {isPending ? "Processing…" : "Sign and execute"}
                  </button>
                </>
              )}
            </>
          )
        ) : (
          <>
            <h2 className="app-card-title">Swap tokens</h2>
            <div className="app-empty app-action-empty">
              <p>
                This X Layer Testnet deployment has no configured Uniswap V3
                adapter. Select TRANSFER for the current flow.
              </p>
            </div>
          </>
        )}
      </div>
    </>
  );
}
