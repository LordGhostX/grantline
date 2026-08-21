"use client";

import { useCallback, useState } from "react";
import { useBalance, useConnection } from "wagmi";
import type { Address } from "viem";
import { AppModal } from "@/components/app/app-modal";
import { CopyAddress } from "@/components/app/copy-address";
import GrantlineMark from "@/components/grantline-mark";
import { TransactionStatus } from "@/components/app/transaction-status";
import { addresses, chainId, grantlineAbi } from "@/lib/contracts";
import {
  formatError,
  formatNativeBalance,
  parseNativeAmount,
} from "@/lib/app-utils";
import { useAppTransaction } from "@/lib/use-app-transaction";
import { useVaults, type VaultInfo } from "@/lib/use-vaults";

function VaultCard({
  vault,
  onRefetch,
  onFund,
  onWithdraw,
}: {
  vault: VaultInfo;
  onRefetch: () => Promise<unknown>;
  onFund: (vault: VaultInfo) => void;
  onWithdraw: (vault: VaultInfo) => void;
}) {
  const transaction = useAppTransaction();
  const [actionError, setActionError] = useState<string | null>(null);

  const handlePauseToggle = useCallback(async () => {
    setActionError(null);

    try {
      await transaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: vault.paused ? "unpauseVault" : "pauseVault",
        args: [vault.address],
      });
      await onRefetch();
    } catch (error) {
      setActionError(formatError(error));
    }
  }, [onRefetch, transaction, vault.address, vault.paused]);

  return (
    <article className="app-card app-vault-card">
      <div className="app-card-heading">
        <div>
          <span className="app-eyebrow">Vault #{vault.index}</span>
          <CopyAddress address={vault.address} label="Vault address" />
        </div>
        <span
          className={`app-tag ${vault.paused ? "app-tag-paused" : "app-tag-active"}`}
        >
          {vault.paused ? "Paused" : "Active"}
        </span>
      </div>

      <dl className="app-detail-grid app-vault-details">
        <div>
          <dt>Native balance</dt>
          <dd>{formatNativeBalance(vault.nativeBalance)}</dd>
        </div>
        <div>
          <dt>Controller</dt>
          <dd>
            <CopyAddress
              address={vault.controller}
              label="Controller address"
            />
          </dd>
        </div>
      </dl>

      <div className="app-card-actions">
        <button
          type="button"
          className="app-btn app-btn-primary"
          onClick={() => onFund(vault)}
          disabled={transaction.isPending}
        >
          Fund
        </button>
        <button
          type="button"
          className="app-btn app-btn-quiet"
          onClick={() => onWithdraw(vault)}
          disabled={transaction.isPending || vault.nativeBalance === 0n}
        >
          Withdraw
        </button>
        <button
          type="button"
          className="app-btn app-btn-quiet"
          onClick={handlePauseToggle}
          disabled={transaction.isPending}
        >
          {transaction.isPending
            ? "Confirming…"
            : vault.paused
              ? "Unpause"
              : "Pause"}
        </button>
      </div>

      <TransactionStatus
        error={actionError ?? transaction.error}
        isPending={transaction.isPending}
        message="Confirm the Vault change in your wallet."
      />
    </article>
  );
}

export default function AppVaults() {
  const { address, isConnected } = useConnection();
  const { vaults, isLoading, error, refetch } = useVaults();
  const wallet = useBalance({ address, chainId });
  const createTransaction = useAppTransaction();
  const fundTransaction = useAppTransaction();
  const withdrawTransaction = useAppTransaction();

  const [showCreate, setShowCreate] = useState(false);
  const [fundTarget, setFundTarget] = useState<VaultInfo | null>(null);
  const [fundAmount, setFundAmount] = useState("");
  const [withdrawTarget, setWithdrawTarget] = useState<VaultInfo | null>(null);
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [createError, setCreateError] = useState<string | null>(null);
  const [fundError, setFundError] = useState<string | null>(null);
  const [withdrawError, setWithdrawError] = useState<string | null>(null);

  const resetCreateTransaction = createTransaction.reset;

  const closeCreate = useCallback(() => {
    if (createTransaction.isPending) return;
    setShowCreate(false);
    setCreateError(null);
    resetCreateTransaction();
  }, [createTransaction.isPending, resetCreateTransaction]);

  const closeFund = useCallback(() => {
    if (fundTransaction.isPending) return;
    setFundTarget(null);
    setFundAmount("");
    setFundError(null);
  }, [fundTransaction.isPending]);

  const closeWithdraw = useCallback(() => {
    if (withdrawTransaction.isPending) return;
    setWithdrawTarget(null);
    setWithdrawAmount("");
    setWithdrawError(null);
  }, [withdrawTransaction.isPending]);

  const handleCreate = useCallback(async () => {
    setCreateError(null);

    try {
      await createTransaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "createVault",
      });
      closeCreate();
      await refetch();
    } catch (error) {
      setCreateError(formatError(error));
    }
  }, [closeCreate, createTransaction, refetch]);

  const handleFund = useCallback(async () => {
    if (!fundTarget) return;
    setFundError(null);

    try {
      const value = parseNativeAmount(fundAmount, "Fund amount");
      if (wallet.data && value > wallet.data.value) {
        throw new Error("The fund amount is greater than your wallet balance.");
      }

      await fundTransaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "depositNative",
        args: [fundTarget.address],
        value,
      });
      closeFund();
      await Promise.all([refetch(), wallet.refetch()]);
    } catch (error) {
      setFundError(formatError(error));
    }
  }, [closeFund, fundAmount, fundTarget, fundTransaction, refetch, wallet]);

  const handleWithdraw = useCallback(async () => {
    if (!withdrawTarget || !address) return;
    setWithdrawError(null);

    try {
      const value = parseNativeAmount(withdrawAmount, "Withdrawal amount");
      if (value > withdrawTarget.nativeBalance) {
        throw new Error(
          "The withdrawal amount is greater than the Vault balance.",
        );
      }

      await withdrawTransaction.submit({
        address: addresses.grantline,
        abi: grantlineAbi,
        functionName: "withdrawNative",
        args: [withdrawTarget.address, address as Address, value],
      });
      closeWithdraw();
      await Promise.all([refetch(), wallet.refetch()]);
    } catch (error) {
      setWithdrawError(formatError(error));
    }
  }, [
    address,
    closeWithdraw,
    refetch,
    withdrawAmount,
    withdrawTarget,
    withdrawTransaction,
    wallet,
  ]);

  function openFund(vault: VaultInfo) {
    setFundTarget(vault);
    setFundAmount("");
    setFundError(null);
  }

  function openWithdraw(vault: VaultInfo) {
    setWithdrawTarget(vault);
    setWithdrawAmount("");
    setWithdrawError(null);
  }

  return (
    <>
      <div className="app-page-header app-page-header-row">
        <div>
          <h1>Vaults</h1>
          <p>
            Create and manage Vaults that hold capital under Grantline
            authority.
          </p>
          <p className="app-page-header-faucet">
            Need testnet OKB?{" "}
            <a
              href="https://web3.okx.com/xlayer/faucet/xlayerfaucet"
              target="_blank"
              rel="noreferrer"
            >
              Get it from the X Layer faucet.
            </a>
          </p>
        </div>
        {isConnected && (
          <button
            type="button"
            className="app-btn app-btn-primary"
            onClick={() => {
              setCreateError(null);
              setShowCreate(true);
            }}
            disabled={createTransaction.isPending}
          >
            Create Vault
          </button>
        )}
      </div>

      {!isConnected && (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>Connect your wallet</h2>
          <p>Connect a wallet to view and manage your testnet Vaults.</p>
        </div>
      )}

      {isConnected && error && (
        <div className="app-alert app-alert-error" role="alert">
          {error}
        </div>
      )}

      {isConnected && isLoading && (
        <div className="app-empty app-card">
          <h2>Loading Vaults…</h2>
          <p>Reading your Vaults from X Layer Testnet.</p>
        </div>
      )}

      {isConnected && !isLoading && !error && vaults.length === 0 && (
        <div className="app-empty app-card">
          <GrantlineMark className="app-empty-icon" />
          <h2>No Vaults yet</h2>
          <p>
            Create a Vault to start holding capital under Grantline authority.
          </p>
          <button
            type="button"
            className="app-btn app-btn-primary"
            onClick={() => setShowCreate(true)}
          >
            Create your first Vault
          </button>
        </div>
      )}

      {isConnected && !isLoading && !error && vaults.length > 0 && (
        <div className="app-card-grid">
          {[...vaults]
            .sort((a, b) => {
              if (a.paused !== b.paused) return a.paused ? 1 : -1;
              return b.index - a.index;
            })
            .map((vault) => (
              <VaultCard
                key={vault.address}
                vault={vault}
                onRefetch={refetch}
                onFund={openFund}
                onWithdraw={openWithdraw}
              />
            ))}
        </div>
      )}

      {showCreate && (
        <AppModal
          title="Create Vault"
          description="This deploys a new testnet Vault under your wallet controller."
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
            <TransactionStatus
              error={createError ?? createTransaction.error}
              isPending={createTransaction.isPending}
              message="Confirm the Vault deployment in your wallet."
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
                disabled={createTransaction.isPending}
              >
                {createTransaction.isPending ? "Confirming…" : "Create Vault"}
              </button>
            </div>
          </form>
        </AppModal>
      )}

      {fundTarget && (
        <AppModal
          title={`Fund Vault #${fundTarget.index}`}
          description="Send OKB from your wallet into this Vault."
          onClose={closeFund}
          closeDisabled={fundTransaction.isPending}
        >
          <form
            className="app-modal-form"
            onSubmit={(event) => {
              event.preventDefault();
              void handleFund();
            }}
          >
            <div className="app-balance-row" aria-live="polite">
              <span>Wallet balance</span>
              <strong>
                {wallet.data
                  ? formatNativeBalance(wallet.data.value)
                  : "Loading…"}
              </strong>
            </div>
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="fund-amount">
                Amount (OKB)
              </label>
              <input
                id="fund-amount"
                className="app-form-input"
                type="text"
                inputMode="decimal"
                autoComplete="off"
                placeholder="0.1"
                value={fundAmount}
                onChange={(event) => setFundAmount(event.target.value)}
              />
            </div>
            <TransactionStatus
              error={fundError ?? fundTransaction.error}
              isPending={fundTransaction.isPending}
              message="Confirm the deposit in your wallet."
            />
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={closeFund}
                disabled={fundTransaction.isPending}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="app-btn app-btn-primary"
                disabled={fundTransaction.isPending || !fundAmount.trim()}
              >
                {fundTransaction.isPending ? "Confirming…" : "Fund Vault"}
              </button>
            </div>
          </form>
        </AppModal>
      )}

      {withdrawTarget && (
        <AppModal
          title={`Withdraw from Vault #${withdrawTarget.index}`}
          description="Withdraw OKB from this Vault to your connected wallet."
          onClose={closeWithdraw}
          closeDisabled={withdrawTransaction.isPending}
        >
          <form
            className="app-modal-form"
            onSubmit={(event) => {
              event.preventDefault();
              void handleWithdraw();
            }}
          >
            <div className="app-balance-row" aria-live="polite">
              <span>Available balance</span>
              <strong>
                {formatNativeBalance(withdrawTarget.nativeBalance)}
              </strong>
            </div>
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="withdraw-amount">
                Amount (OKB)
              </label>
              <input
                id="withdraw-amount"
                className="app-form-input"
                type="text"
                inputMode="decimal"
                autoComplete="off"
                placeholder="0.1"
                value={withdrawAmount}
                onChange={(event) => setWithdrawAmount(event.target.value)}
              />
            </div>
            <TransactionStatus
              error={withdrawError ?? withdrawTransaction.error}
              isPending={withdrawTransaction.isPending}
              message="Confirm the withdrawal in your wallet."
            />
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={closeWithdraw}
                disabled={withdrawTransaction.isPending}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="app-btn app-btn-primary"
                disabled={
                  withdrawTransaction.isPending || !withdrawAmount.trim()
                }
              >
                {withdrawTransaction.isPending ? "Confirming…" : "Withdraw"}
              </button>
            </div>
          </form>
        </AppModal>
      )}
    </>
  );
}
