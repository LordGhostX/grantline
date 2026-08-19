"use client";

import { useState, useCallback } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSwitchChain,
  useBalance,
} from "wagmi";
import { parseEther } from "viem";
import { addresses, grantlineAbi, chainId } from "@/lib/contracts";
import { useVaults, type VaultInfo } from "@/lib/use-vaults";

function truncateAddress(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function formatBalance(wei: bigint) {
  const eth = Number(wei) / 1e18;
  if (eth === 0) return "0 OKB";
  if (eth < 0.001) return "<0.001 OKB";
  return `${eth.toFixed(4)} OKB`;
}

function formatError(err: unknown): string {
  if (!err) return "";
  if (err instanceof Error) {
    return "shortMessage" in err ? String(err.shortMessage) : err.message;
  }
  return String(err);
}

function VaultCard({
  vault,
  onFund,
  onWithdraw,
  onRefetch,
  switchChain,
}: {
  vault: VaultInfo;
  onFund: (vault: VaultInfo) => void;
  onWithdraw: (vault: VaultInfo) => void;
  onRefetch: () => void;
  switchChain: ReturnType<typeof useSwitchChain>["switchChain"];
}) {
  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: txLoading } = useWaitForTransactionReceipt({
    hash: txHash,
  });
  const [pauseError, setPauseError] = useState<string | null>(null);

  const handlePauseToggle = useCallback(async () => {
    setPauseError(null);
    try {
      await switchChain({ chainId });
      const fn = vault.paused ? "unpauseVault" : "pauseVault";
      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: fn,
          args: [vault.address],
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
  }, [vault, writeContract, onRefetch, switchChain]);

  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(vault.address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, [vault.address]);

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
            Vault #{vault.index}
          </div>
          <div
            className="app-code"
            style={{ cursor: "pointer" }}
            title={vault.address}
            onClick={handleCopy}
          >
            {copied ? "Copied!" : truncateAddress(vault.address)}
          </div>
        </div>
        <span
          className={
            vault.paused ? "app-tag app-tag-paused" : "app-tag app-tag-active"
          }
        >
          {vault.paused ? "Paused" : "Active"}
        </span>
      </div>

      <div style={{ marginBottom: 20 }}>
        <div style={{ fontSize: 13, color: "#9a9896", marginBottom: 4 }}>
          Balance
        </div>
        <div style={{ fontSize: 20, fontWeight: 600 }}>
          {formatBalance(vault.nativeBalance)}
        </div>
      </div>

      <div style={{ display: "flex", gap: 8 }}>
        <button
          type="button"
          className="app-btn app-btn-primary"
          style={{ flex: 1 }}
          onClick={() => onFund(vault)}
        >
          Fund
        </button>
        <button
          type="button"
          className="app-btn app-btn-quiet"
          style={{ flex: 1 }}
          onClick={() => onWithdraw(vault)}
          disabled={vault.nativeBalance === BigInt(0)}
        >
          Withdraw
        </button>
        <button
          type="button"
          className="app-btn app-btn-quiet"
          style={{ flex: 1 }}
          disabled={isPending || txLoading}
          onClick={handlePauseToggle}
        >
          {isPending || txLoading
            ? "Waiting…"
            : vault.paused
              ? "Unpause"
              : "Pause"}
        </button>
      </div>
      {pauseError && (
        <div
          style={{ marginTop: 8, fontSize: 12, color: "var(--deny, #d97878)" }}
        >
          {pauseError}
        </div>
      )}
    </div>
  );
}

export default function AppVaults() {
  const { address, isConnected } = useAccount();
  const { vaults, isLoading, refetch } = useVaults();
  const { writeContract } = useWriteContract();
  const { switchChain } = useSwitchChain();
  const { data: walletBalance, refetch: refetchBalance } = useBalance({
    address,
  });

  const [showCreate, setShowCreate] = useState(false);
  const [fundTarget, setFundTarget] = useState<VaultInfo | null>(null);
  const [fundAmount, setFundAmount] = useState("");
  const [withdrawTarget, setWithdrawTarget] = useState<VaultInfo | null>(null);
  const [withdrawAmount, setWithdrawAmount] = useState("");

  const [createError, setCreateError] = useState<string | null>(null);
  const [fundError, setFundError] = useState<string | null>(null);
  const [withdrawError, setWithdrawError] = useState<string | null>(null);

  const handleCreate = useCallback(async () => {
    setCreateError(null);
    try {
      await switchChain({ chainId });
      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "createVault",
          chainId,
        },
        {
          onSuccess: () => {
            setShowCreate(false);
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
  }, [writeContract, refetch, switchChain]);

  const handleFund = useCallback(async () => {
    if (!fundTarget || !fundAmount) return;
    setFundError(null);
    try {
      await switchChain({ chainId });
      const value = parseEther(fundAmount);
      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "depositNative",
          args: [fundTarget.address],
          value,
          chainId,
        },
        {
          onSuccess: () => {
            setFundTarget(null);
            setFundAmount("");
            setTimeout(() => {
              refetch();
              refetchBalance();
            }, 1500);
          },
          onError: (err) => {
            setFundError(formatError(err));
          },
        },
      );
    } catch (err) {
      setFundError(formatError(err));
    }
  }, [
    fundTarget,
    fundAmount,
    writeContract,
    refetch,
    refetchBalance,
    switchChain,
  ]);

  const handleWithdraw = useCallback(async () => {
    if (!withdrawTarget || !withdrawAmount || !address) return;
    setWithdrawError(null);
    try {
      await switchChain({ chainId });
      const value = parseEther(withdrawAmount);
      writeContract(
        {
          address: addresses.grantline,
          abi: grantlineAbi,
          functionName: "withdrawNative",
          args: [withdrawTarget.address, address, value],
          chainId,
        },
        {
          onSuccess: () => {
            setWithdrawTarget(null);
            setWithdrawAmount("");
            setTimeout(() => {
              refetch();
              refetchBalance();
            }, 1500);
          },
          onError: (err) => {
            setWithdrawError(formatError(err));
          },
        },
      );
    } catch (err) {
      setWithdrawError(formatError(err));
    }
  }, [
    withdrawTarget,
    withdrawAmount,
    address,
    writeContract,
    refetch,
    refetchBalance,
    switchChain,
  ]);

  return (
    <>
      <div className="app-page-header">
        <h1>Vaults</h1>
        <p>Create and manage Vault contracts that hold controlled capital.</p>
      </div>

      {isConnected && (
        <div style={{ marginBottom: 24 }}>
          <button
            type="button"
            className="app-btn app-btn-primary"
            onClick={() => setShowCreate(true)}
          >
            Create Vault
          </button>
        </div>
      )}

      {!isConnected && (
        <div className="app-empty">
          <div className="app-empty-icon">🏦</div>
          <h3>Connect your wallet</h3>
          <p>Connect a wallet to view and manage your Vaults.</p>
        </div>
      )}

      {isConnected && isLoading && (
        <div className="app-empty">
          <h3>Loading vaults…</h3>
        </div>
      )}

      {isConnected && !isLoading && vaults.length === 0 && (
        <div className="app-empty">
          <div className="app-empty-icon">🏦</div>
          <h3>No vaults yet</h3>
          <p>
            Create a Vault to start holding capital under Grantline authority.
          </p>
        </div>
      )}

      {isConnected && !isLoading && vaults.length > 0 && (
        <div className="app-card-grid">
          {vaults.map((v) => (
            <VaultCard
              key={v.address}
              vault={v}
              onFund={setFundTarget}
              onWithdraw={setWithdrawTarget}
              onRefetch={refetch}
              switchChain={switchChain}
            />
          ))}
        </div>
      )}

      {/* Create Vault Modal */}
      {showCreate && (
        <div
          className="app-modal-backdrop"
          onClick={() => setShowCreate(false)}
        >
          <div className="app-modal" onClick={(e) => e.stopPropagation()}>
            <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>Create Vault</h3>
            <p style={{ margin: 0, fontSize: 14, color: "#9a9896" }}>
              This will deploy a new Vault contract under your control.
            </p>
            {createError && (
              <div
                style={{
                  marginTop: 12,
                  fontSize: 12,
                  color: "var(--deny, #d97878)",
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
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Fund Vault Modal */}
      {fundTarget && (
        <div
          className="app-modal-backdrop"
          onClick={() => {
            setFundTarget(null);
            setFundAmount("");
          }}
        >
          <div className="app-modal" onClick={(e) => e.stopPropagation()}>
            <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>
              Fund Vault #{fundTarget.index}
            </h3>
            <p
              style={{
                margin: 0,
                fontSize: 14,
                color: "#9a9896",
                marginBottom: 20,
              }}
            >
              Send OKB to Vault #{fundTarget.index}.
            </p>
            {walletBalance && (
              <div style={{ marginBottom: 16, fontSize: 13, color: "#9a9896" }}>
                Your balance:{" "}
                {(
                  Number(walletBalance.value) /
                  10 ** walletBalance.decimals
                ).toFixed(4)}{" "}
                {walletBalance.symbol}
              </div>
            )}
            {fundError && (
              <div
                style={{
                  marginBottom: 16,
                  fontSize: 12,
                  color: "var(--deny, #d97878)",
                }}
              >
                {fundError}
              </div>
            )}
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="fund-amount">
                Amount (OKB)
              </label>
              <input
                id="fund-amount"
                className="app-form-input"
                type="number"
                step="0.001"
                min="0"
                placeholder="0.0"
                value={fundAmount}
                onChange={(e) => setFundAmount(e.target.value)}
              />
            </div>
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={() => {
                  setFundTarget(null);
                  setFundAmount("");
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                className="app-btn app-btn-primary"
                onClick={handleFund}
                disabled={!fundAmount || Number(fundAmount) <= 0}
              >
                Fund
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Withdraw Modal */}
      {withdrawTarget && (
        <div
          className="app-modal-backdrop"
          onClick={() => {
            setWithdrawTarget(null);
            setWithdrawAmount("");
          }}
        >
          <div className="app-modal" onClick={(e) => e.stopPropagation()}>
            <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>
              Withdraw from Vault #{withdrawTarget.index}
            </h3>
            <p
              style={{
                margin: 0,
                fontSize: 14,
                color: "#9a9896",
                marginBottom: 20,
              }}
            >
              Withdraw OKB from Vault #{withdrawTarget.index} to your wallet.
            </p>
            <div style={{ marginBottom: 16, fontSize: 13, color: "#9a9896" }}>
              Vault balance: {formatBalance(withdrawTarget.nativeBalance)}
            </div>
            {withdrawError && (
              <div
                style={{
                  marginBottom: 16,
                  fontSize: 12,
                  color: "var(--deny, #d97878)",
                }}
              >
                {withdrawError}
              </div>
            )}
            <div className="app-form-group">
              <label className="app-form-label" htmlFor="withdraw-amount">
                Amount (OKB)
              </label>
              <input
                id="withdraw-amount"
                className="app-form-input"
                type="number"
                step="0.001"
                min="0"
                max={Number(withdrawTarget.nativeBalance) / 1e18}
                placeholder="0.0"
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
              />
            </div>
            <div className="app-modal-actions">
              <button
                type="button"
                className="app-btn app-btn-quiet"
                onClick={() => {
                  setWithdrawTarget(null);
                  setWithdrawAmount("");
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                className="app-btn app-btn-primary"
                onClick={handleWithdraw}
                disabled={
                  !withdrawAmount ||
                  Number(withdrawAmount) <= 0 ||
                  Number(withdrawAmount) >
                    Number(withdrawTarget.nativeBalance) / 1e18
                }
              >
                Withdraw
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
