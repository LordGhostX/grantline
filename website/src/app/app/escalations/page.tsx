"use client";

import { useCallback, useState } from "react";
import { useConnection } from "wagmi";
import { CopyAddress } from "@/components/app/copy-address";
import GrantlineMark from "@/components/grantline-mark";
import { TransactionStatus } from "@/components/app/transaction-status";
import { addresses, grantlineAbi } from "@/lib/contracts";
import { decodeAction, type DecodedAction } from "@/lib/action-plan";
import { formatDate, formatError, formatNative } from "@/lib/app-utils";
import {
  getEscalationStatusLabel,
  type EscalationData,
  useEscalations,
} from "@/lib/use-escalations";
import { useAppTransaction } from "@/lib/use-app-transaction";
import { zeroAddress, type Address } from "viem";

function ActionAsset({ asset }: { asset: Address }) {
  if (asset.toLowerCase() === zeroAddress) {
    return <>OKB (native)</>;
  }

  return <CopyAddress address={asset} label="Token address" />;
}

function ActionAssetAmount({
  amount,
  asset,
}: {
  amount: bigint;
  asset: Address;
}) {
  if (asset.toLowerCase() === zeroAddress) {
    return <>{formatNative(amount)} OKB</>;
  }

  return (
    <>
      {amount.toString()} token units of <ActionAsset asset={asset} />
    </>
  );
}

function swapAdapterLabel(adapterId: number): string {
  return adapterId === 1 ? "Uniswap V3 (#1)" : `Adapter #${adapterId}`;
}

function SwapRoute({
  action,
}: {
  action: Extract<DecodedAction, { kind: "swap" }>;
}) {
  return (
    <div className="app-escalation-route">
      <span className="app-escalation-route-label">
        Route · {swapAdapterLabel(action.adapterId)}
      </span>
      <ol>
        {action.hops.map((hop, index) => (
          <li
            key={`${hop.pool}-${hop.tokenIn}-${hop.tokenOut}-${index}`}
            className="app-escalation-route-step"
          >
            <span className="app-escalation-route-index">{index + 1}.</span>
            <span>
              <ActionAsset asset={hop.tokenIn} />
              <span className="app-escalation-route-arrow" aria-hidden="true">
                →
              </span>
              <ActionAsset asset={hop.tokenOut} /> {" via "}
              <CopyAddress address={hop.pool} label="Pool address" />
            </span>
          </li>
        ))}
      </ol>
    </div>
  );
}

function EscalationActionSummary({
  action,
  index,
}: {
  action: EscalationData["plan"]["actions"][number];
  index: number;
}) {
  const decoded = decodeAction(action);

  return (
    <li className="app-escalation-action">
      <div className="app-escalation-action-line">
        <span className="app-escalation-action-index">{index + 1}.</span>
        {decoded.kind === "transfer" && (
          <span>
            Transfer{" "}
            <ActionAssetAmount amount={decoded.amount} asset={decoded.asset} />{" "}
            to{" "}
            <CopyAddress
              address={decoded.recipient}
              label="Recipient address"
            />
          </span>
        )}
        {decoded.kind === "swap" && (
          <span>
            Swap{" "}
            <ActionAssetAmount
              amount={decoded.amountIn}
              asset={decoded.tokenIn}
            />{" "}
            for at least{" "}
            <ActionAssetAmount
              amount={decoded.minAmountOut}
              asset={decoded.tokenOut}
            />
          </span>
        )}
        {decoded.kind === "unknown" && (
          <span>
            Action type {decoded.actionType}, version {decoded.version};
            parameters could not be decoded.
          </span>
        )}
      </div>
      {decoded.kind === "swap" && <SwapRoute action={decoded} />}
      {decoded.kind === "unknown" && (
        <code className="app-escalation-raw-parameters">
          {decoded.parameters}
        </code>
      )}
    </li>
  );
}

function statusClass(status: number): string {
  if (status === 1) return "app-tag-paused";
  if (status === 2 || status === 4) return "app-tag-active";
  return "app-tag-revoked";
}

function EscalationCard({
  escalation,
  onRefetch,
}: {
  escalation: EscalationData;
  onRefetch: () => Promise<unknown>;
}) {
  const transaction = useAppTransaction();
  const [actionError, setActionError] = useState<string | null>(null);
  const label = getEscalationStatusLabel(escalation.status);
  const isPending = escalation.status === 1;
  const isApproved = escalation.status === 2;
  const hasActions = isPending || isApproved;

  const submitAction = useCallback(
    async (
      functionName: "approveEscalation" | "denyEscalation" | "executeEscalated",
    ) => {
      setActionError(null);
      try {
        await transaction.submit({
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName,
          args: [escalation.digest],
        });
        await onRefetch();
      } catch (error) {
        setActionError(formatError(error));
      }
    },
    [escalation.digest, onRefetch, transaction],
  );

  return (
    <article className="app-card app-escalation-card">
      <div className="app-card-heading">
        <div>
          <span className="app-eyebrow">
            Mandate #{escalation.plan.mandateId.toString()}
          </span>
          <CopyAddress address={escalation.vault} label="Vault address" />
        </div>
        <span className={`app-tag ${statusClass(escalation.status)}`}>
          {label}
        </span>
      </div>

      <dl className="app-detail-grid">
        <div>
          <dt>Agent</dt>
          <dd>
            <CopyAddress
              address={escalation.plan.agent}
              label="Agent address"
            />
          </dd>
        </div>
        <div>
          <dt>Submitted by</dt>
          <dd>
            <CopyAddress
              address={escalation.submittedBy}
              label="Submitter address"
            />
          </dd>
        </div>
      </dl>

      <div className="app-escalation-actions">
        <h3>Action plan</h3>
        <ol>
          {escalation.plan.actions.map((action, index) => (
            <EscalationActionSummary
              key={`${action.actionType}-${action.version}-${index}`}
              action={action}
              index={index}
            />
          ))}
        </ol>
      </div>

      <div
        className={`app-escalation-meta${hasActions ? "" : " app-escalation-meta-final"}`}
      >
        <span>Submitted</span>
        <span>{formatDate(escalation.submittedAt)}</span>
      </div>

      {hasActions && (
        <div className="app-card-actions">
          {isPending && (
            <>
              <button
                type="button"
                className="app-btn app-btn-primary"
                onClick={() => submitAction("approveEscalation")}
                disabled={transaction.isPending}
              >
                Approve
              </button>
              <button
                type="button"
                className="app-btn app-btn-danger"
                onClick={() => submitAction("denyEscalation")}
                disabled={transaction.isPending}
              >
                Deny
              </button>
            </>
          )}
          {isApproved && (
            <button
              type="button"
              className="app-btn app-btn-primary"
              onClick={() => submitAction("executeEscalated")}
              disabled={transaction.isPending}
            >
              Execute approved plan
            </button>
          )}
        </div>
      )}

      <TransactionStatus
        error={actionError ?? transaction.error}
        isPending={transaction.isPending}
        message="Confirm the Escalation action in your wallet."
      />
    </article>
  );
}

export default function AppEscalations() {
  const { isConnected } = useConnection();
  const { escalations, isLoading, error, refetch } = useEscalations();

  return (
    <>
      <div className="app-page-header">
        <h1>Escalations</h1>
        <p>
          Action Plans that exceeded their authority, awaiting review or showing
          their final outcome.
        </p>
      </div>

      {!isConnected && (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>Connect your wallet</h2>
          <p>Connect your wallet to review Mandate escalations.</p>
        </div>
      )}

      {isConnected && error && (
        <div className="app-alert app-alert-error" role="alert">
          {error}
        </div>
      )}

      {isConnected && isLoading && (
        <div className="app-empty app-card">
          <h2>Loading Escalations…</h2>
          <p>Reading your Escalations from X Layer Testnet.</p>
        </div>
      )}

      {isConnected && !isLoading && !error && escalations.length === 0 && (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>No escalations yet</h2>
          <p>
            When an Action Plan exceeds its authority, the proposal appears here
            for approval or denial.
          </p>
        </div>
      )}

      {isConnected && !isLoading && !error && escalations.length > 0 && (
        <div className="app-card-grid">
          {escalations.map((escalation) => (
            <EscalationCard
              key={escalation.digest}
              escalation={escalation}
              onRefetch={refetch}
            />
          ))}
        </div>
      )}
    </>
  );
}
