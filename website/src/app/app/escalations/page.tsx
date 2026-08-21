"use client";

import { useCallback, useState } from "react";
import { useConnection } from "wagmi";
import { CopyAddress } from "@/components/app/copy-address";
import GrantlineMark from "@/components/grantline-mark";
import { TransactionStatus } from "@/components/app/transaction-status";
import { addresses, grantlineAbi } from "@/lib/contracts";
import { formatDate, formatError } from "@/lib/app-utils";
import {
  getEscalationStatusLabel,
  type EscalationData,
  useEscalations,
} from "@/lib/use-escalations";
import { useAppTransaction } from "@/lib/use-app-transaction";

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
        <div>
          <dt>Nonce</dt>
          <dd>{escalation.plan.nonce.toString()}</dd>
        </div>
        <div>
          <dt>Actions</dt>
          <dd>{escalation.plan.actions.length}</dd>
        </div>
      </dl>

      <div className="app-escalation-meta">
        <span>Submitted</span>
        <span>{formatDate(escalation.submittedAt)}</span>
      </div>

      {(isPending || isApproved) && (
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
          Proposals that exceeded their authority and await controller review.
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
