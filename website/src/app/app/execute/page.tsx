"use client";

import { useEffect, useState } from "react";
import { encodeAbiParameters, zeroAddress, type Hex } from "viem";
import {
  useConnection,
  usePublicClient,
  useSignTypedData,
  useSwitchChain,
} from "wagmi";
import { TransactionStatus } from "@/components/app/transaction-status";
import GrantlineMark from "@/components/grantline-mark";
import {
  addresses,
  chainId,
  demoAgent,
  grantlineAbi,
  xLayerTestnetExplorerUrl,
} from "@/lib/contracts";
import { requestDemoAgentSignature } from "@/lib/demo-agent";
import {
  assertFutureTimestamp,
  parseAddress,
  parseNativeAmount,
} from "@/lib/app-utils";
import {
  actionPlanDomain,
  actionTypes,
  demoAgentAuthorizationDomain,
  demoAgentAuthorizationTtlSeconds,
  demoAgentAuthorizationTypes,
  hashActionPlan,
  type ActionPlan,
} from "@/lib/action-plan";
import { useAppTransaction } from "@/lib/use-app-transaction";
import { getMandateStatusLabel, useMandates } from "@/lib/use-mandates";

type ActionTab = "transfer" | "swap";
type PlanDecision = "allow" | "escalate";
type SubmissionKind = "executed" | "escalation-submitted";
type PendingExecution = {
  plan: ActionPlan;
  signature: Hex;
  decision: PlanDecision | null;
  signedAt: number;
};

type EvaluationResult = {
  decision: number;
  failureCode: number;
};

type EvaluationOutcome = { decision: PlanDecision } | { denial: string };

const MINIMUM_SIGNING_INTERVAL_MS = 500;

const evaluationFailureMessages: Record<number, string> = {
  1: "the Vault is paused",
  2: "the Mandate does not exist",
  3: "the Mandate is inactive",
  4: "the Mandate is not valid yet",
  5: "the Mandate has expired",
  6: "the Mandate is paused",
  7: "the agent does not match the Mandate",
  8: "the Action Plan signature is invalid",
  9: "the Action Plan has expired",
  10: "the nonce has already been used",
  11: "the nonce is already reserved",
  12: "the Action Plan is empty",
  13: "the Action Plan contains an invalid action",
  14: "the Action Plan parameters are invalid",
  15: "the recipient is invalid",
  16: "the amount is invalid",
  17: "the amount overflowed the supported range",
  18: "the amount is below the Mandate minimum",
  19: "the amount exceeds the Mandate maximum",
  20: "the native amount is below its USD minimum",
  21: "the native amount exceeds its USD maximum",
  22: "native USD valuation is unavailable",
  23: "the Vault would fall below its native balance reserve",
  24: "the Vault would fall below its native USD reserve",
  25: "SWAP is not supported",
  26: "the SWAP parameters are invalid",
  27: "the SWAP route is invalid",
};

function getPerformanceTimestamp(): number {
  return performance.now();
}

async function waitForMinimumSigningInterval(startedAt: number) {
  const remaining =
    MINIMUM_SIGNING_INTERVAL_MS - (performance.now() - startedAt);
  if (remaining <= 0) return;

  await new Promise<void>((resolve) => {
    setTimeout(resolve, remaining);
  });
}

function nextDemoNonce(previous = ""): string {
  const current = BigInt(Math.floor(Date.now() / 1000));
  if (!/^\d+$/.test(previous)) return current.toString();

  const previousNonce = BigInt(previous);
  return (current > previousNonce ? current : previousNonce + 1n).toString();
}

function nextDemoAuthorizationExpiry(): bigint {
  return (
    BigInt(Math.floor(Date.now() / 1000)) +
    BigInt(demoAgentAuthorizationTtlSeconds)
  );
}

function formatEvaluationDenial(failureCode: number): string {
  return `Grantline denied this Action Plan: ${evaluationFailureMessages[failureCode] ?? `validation failed (code ${failureCode})`}.`;
}

export default function AppExecute() {
  const { address, chainId: connectedChainId, isConnected } = useConnection();
  const publicClient = usePublicClient({ chainId });
  const {
    mandates,
    isLoading: mandatesLoading,
    error: mandatesError,
  } = useMandates({ scope: "all", enabled: isConnected });
  const signTypedData = useSignTypedData();
  const signControllerAuthorization = useSignTypedData();
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
  const [isDemoSigning, setIsDemoSigning] = useState(false);
  const [isEvaluating, setIsEvaluating] = useState(false);
  const [isPreparingExecution, setIsPreparingExecution] = useState(false);
  const [submissionKind, setSubmissionKind] = useState<SubmissionKind | null>(
    null,
  );
  const [pendingExecution, setPendingExecution] =
    useState<PendingExecution | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => setNonce(nextDemoNonce()), 0);
    return () => window.clearTimeout(timer);
  }, []);

  const activeMandates = mandates
    .filter((mandate) => mandate.status === 0)
    .sort((left, right) => {
      if (left.id === right.id) return 0;
      return left.id > right.id ? -1 : 1;
    });
  const selectedMandate =
    activeMandates.find((mandate) => mandate.id.toString() === mandateId) ??
    activeMandates[0];
  const mandatesReady = !mandatesLoading && !mandatesError;
  const usesDemoAgent =
    Boolean(selectedMandate) &&
    selectedMandate!.agent.toLowerCase() === demoAgent.toLowerCase();
  const connectedWalletMatchesAgent =
    Boolean(address && selectedMandate) &&
    address!.toLowerCase() === selectedMandate!.agent.toLowerCase();
  const connectedWalletMatchesController =
    Boolean(address && selectedMandate) &&
    address!.toLowerCase() === selectedMandate!.controller.toLowerCase();
  const canSignActionPlan =
    Boolean(selectedMandate) &&
    (usesDemoAgent
      ? connectedWalletMatchesController
      : connectedWalletMatchesAgent);
  const isPending =
    isDemoSigning ||
    isEvaluating ||
    isPreparingExecution ||
    signTypedData.isPending ||
    signControllerAuthorization.isPending ||
    switchChain.isPending ||
    transaction.isPending;
  const error =
    flowError ??
    signControllerAuthorization.error ??
    signTypedData.error ??
    switchChain.error ??
    transaction.error;
  const transactionExplorerUrl = transactionHash
    ? `${xLayerTestnetExplorerUrl}/tx/${transactionHash}`
    : null;

  async function evaluateActionPlan(
    plan: ActionPlan,
    signature: Hex,
  ): Promise<EvaluationOutcome> {
    if (!publicClient) {
      throw new Error("Unable to read Grantline on X Layer Testnet.");
    }

    setIsEvaluating(true);
    try {
      const evaluation = (await publicClient.readContract({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "evaluate",
        args: [plan, signature],
      })) as EvaluationResult;

      if (Number(evaluation.decision) === 0) return { decision: "allow" };
      if (Number(evaluation.decision) === 1) {
        return { decision: "escalate" };
      }

      return {
        denial: formatEvaluationDenial(Number(evaluation.failureCode)),
      };
    } finally {
      setIsEvaluating(false);
    }
  }

  async function resolvePendingDecision(
    pending: PendingExecution,
  ): Promise<PlanDecision> {
    const outcome = await evaluateActionPlan(pending.plan, pending.signature);
    if ("denial" in outcome) {
      setPendingExecution(null);
      throw new Error(outcome.denial);
    }

    const resolved = { ...pending, decision: outcome.decision };
    setPendingExecution(resolved);
    return outcome.decision;
  }

  async function submitActionPlan(
    plan: ActionPlan,
    signature: Hex,
    decision: PlanDecision,
    skipChainSwitch: boolean,
  ) {
    const hash = await transaction.submit(
      {
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: decision === "allow" ? "execute" : "submitEscalation",
        args: [plan, signature],
      },
      { skipChainSwitch },
    );
    setTransactionHash(hash);
    setSubmissionKind(
      decision === "allow" ? "executed" : "escalation-submitted",
    );
    setNonce((currentNonce) => nextDemoNonce(currentNonce));
    setPendingExecution(null);
  }

  async function handlePendingExecution() {
    if (!pendingExecution) return;

    setFlowError(null);
    try {
      const decision =
        pendingExecution.decision ??
        (await resolvePendingDecision(pendingExecution));
      setIsPreparingExecution(true);
      await waitForMinimumSigningInterval(pendingExecution.signedAt);
      await submitActionPlan(
        pendingExecution.plan,
        pendingExecution.signature,
        decision,
        false,
      );
    } catch (submissionError) {
      setFlowError(submissionError);
    } finally {
      setIsPreparingExecution(false);
    }
  }

  function clearPendingExecution() {
    setPendingExecution(null);
    setFlowError(null);
  }

  async function handleTransfer() {
    setFlowError(null);
    setTransactionHash(null);
    setIsDemoSigning(false);
    setIsEvaluating(false);
    setIsPreparingExecution(false);
    setSubmissionKind(null);
    setPendingExecution(null);
    signTypedData.reset();
    signControllerAuthorization.reset();
    switchChain.reset();
    transaction.reset();

    try {
      if (!address) {
        throw new Error("Connect a wallet to submit this Action Plan.");
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
      if (usesDemoAgent && !connectedWalletMatchesController) {
        throw new Error(
          `Connect the controller wallet ${selectedMandate.controller} to authorize this Action Plan.`,
        );
      }
      if (!usesDemoAgent && !connectedWalletMatchesAgent) {
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
      let deadlineSeconds = 0n;
      if (deadline) {
        const parsedDeadline = new Date(deadline).getTime();
        if (!Number.isFinite(parsedDeadline)) {
          throw new Error("Deadline must be a valid date.");
        }
        deadlineSeconds = BigInt(Math.floor(parsedDeadline / 1000));
        assertFutureTimestamp(deadlineSeconds, "Deadline");
      }

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
      const plan: ActionPlan = {
        mandateId: selectedMandate.id,
        agent: selectedMandate.agent,
        nonce: BigInt(parsedNonce),
        deadline: deadlineSeconds,
        actions: [{ actionType: 0, version: 1, parameters }],
      };

      let signature: Hex;
      if (usesDemoAgent) {
        const authorization = {
          mandateId: plan.mandateId,
          agent: plan.agent,
          actionDigest: hashActionPlan(plan),
          expiresAt: nextDemoAuthorizationExpiry(),
        };
        const controllerSignature =
          await signControllerAuthorization.mutateAsync({
            domain: demoAgentAuthorizationDomain,
            types: demoAgentAuthorizationTypes,
            primaryType: "DemoAgentAuthorization",
            message: authorization,
          });

        setIsDemoSigning(true);
        try {
          signature = await requestDemoAgentSignature(plan, {
            ...authorization,
            signature: controllerSignature,
          });
        } finally {
          setIsDemoSigning(false);
        }
      } else {
        signature = await signTypedData.mutateAsync({
          domain: actionPlanDomain,
          types: actionTypes,
          primaryType: "ActionPlan",
          message: plan,
        });
      }

      const signedAt = getPerformanceTimestamp();
      const pending = { plan, signature, decision: null, signedAt };
      setPendingExecution(pending);
      const outcome = await evaluateActionPlan(plan, signature);
      if ("denial" in outcome) {
        setPendingExecution(null);
        throw new Error(outcome.denial);
      }

      const decision = outcome.decision;
      setPendingExecution({ ...pending, decision });
      setIsPreparingExecution(true);
      try {
        await waitForMinimumSigningInterval(signedAt);
        await submitActionPlan(plan, signature, decision, true);
      } finally {
        setIsPreparingExecution(false);
      }
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
          <p>
            Connect the controller wallet for demo Mandates or the agent wallet
            for standard Mandates.
          </p>
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
          disabled={isPending}
          onClick={() => {
            clearPendingExecution();
            setTab("transfer");
          }}
        >
          TRANSFER
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === "swap"}
          className={`app-tab${tab === "swap" ? " active" : ""}`}
          disabled={isPending}
          onClick={() => {
            clearPendingExecution();
            setTab("swap");
          }}
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
                usesDemoAgent && (
                  <>
                    <p className="app-alert app-alert-info" role="status">
                      Your connected controller wallet will authorize this
                      Action Plan. Grantline will sign it with the demo agent on
                      the server, then your wallet will submit it for execution
                      or controller approval.
                    </p>
                    <p className="app-execute-note" role="note">
                      Demo agent wallet: <strong>{demoAgent}</strong>
                    </p>
                  </>
                )}

              {mandatesReady &&
                isConnected &&
                selectedMandate &&
                usesDemoAgent &&
                !connectedWalletMatchesController && (
                  <p className="app-alert app-alert-warning" role="status">
                    Connect the controller wallet for this Mandate before
                    authorizing. The current wallet is {address}.
                  </p>
                )}

              {mandatesReady &&
                isConnected &&
                selectedMandate &&
                !usesDemoAgent &&
                !connectedWalletMatchesAgent && (
                  <>
                    <p className="app-alert app-alert-warning" role="status">
                      Connect the agent wallet for this Mandate before signing.
                      The current wallet is {address}.
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
                        disabled={isPending}
                        onChange={(event) => {
                          clearPendingExecution();
                          setMandateId(event.target.value);
                        }}
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
                      disabled={isPending}
                      onChange={(event) => {
                        clearPendingExecution();
                        setRecipient(event.target.value);
                      }}
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
                        disabled={isPending}
                        onChange={(event) => {
                          clearPendingExecution();
                          setAmount(event.target.value);
                        }}
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
                        disabled={isPending}
                        onChange={(event) => {
                          clearPendingExecution();
                          setNonce(event.target.value);
                        }}
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
                      Deadline (optional)
                    </label>
                    <input
                      id="transfer-deadline"
                      className="app-form-input"
                      type="datetime-local"
                      value={deadline}
                      disabled={isPending}
                      onChange={(event) => {
                        clearPendingExecution();
                        setDeadline(event.target.value);
                      }}
                    />
                    <p className="app-form-hint">
                      Leave blank for no deadline, or choose a future local time
                      so the signed plan expires after that point.
                    </p>
                  </div>

                  <TransactionStatus
                    error={error}
                    isPending={isPending}
                    message={
                      switchChain.isPending
                        ? "Switch to X Layer Testnet in your wallet…"
                        : signControllerAuthorization.isPending
                          ? "Authorize the Action Plan in your wallet…"
                          : isDemoSigning
                            ? "Requesting the demo agent signature…"
                            : isEvaluating
                              ? "Checking the Action Plan with Grantline…"
                              : isPreparingExecution
                                ? "Preparing the submission transaction…"
                                : signTypedData.isPending
                                  ? "Sign the Action Plan in your wallet…"
                                  : "Confirm the transaction in your wallet…"
                    }
                  />

                  {pendingExecution && flowError && !isPending && (
                    <p className="app-alert app-alert-info" role="status">
                      {pendingExecution.decision === null
                        ? "Action Plan signed. Retry the Grantline evaluation without signing again."
                        : "Action Plan signed. Retry the submission to open your wallet and send it again."}
                    </p>
                  )}

                  {transactionHash && (
                    <p
                      className={`app-alert ${submissionKind === "escalation-submitted" ? "app-alert-warning" : "app-alert-info"}`}
                      role="status"
                    >
                      {submissionKind === "escalation-submitted"
                        ? "Action Plan escalated for controller approval. Transaction:"
                        : "Action Plan executed. Transaction:"}{" "}
                      {transactionExplorerUrl ? (
                        <a
                          className="app-code"
                          href={transactionExplorerUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          aria-label="View transaction on the X Layer Testnet Explorer"
                        >
                          {transactionHash}
                        </a>
                      ) : (
                        <span className="app-code">{transactionHash}</span>
                      )}
                    </p>
                  )}

                  <button
                    type="button"
                    className="app-btn app-btn-primary app-execute-submit"
                    disabled={
                      isPending ||
                      !nonce.trim() ||
                      (!pendingExecution &&
                        (!selectedMandate || !canSignActionPlan))
                    }
                    onClick={() =>
                      void (pendingExecution
                        ? handlePendingExecution()
                        : handleTransfer())
                    }
                  >
                    {isPending
                      ? "Processing…"
                      : pendingExecution && flowError
                        ? pendingExecution.decision === null
                          ? "Retry evaluation"
                          : pendingExecution.decision === "escalate"
                            ? "Retry submission"
                            : "Retry execution"
                        : "Sign and execute"}
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
