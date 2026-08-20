"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  useSwitchChain,
} from "wagmi";
import { chainId } from "@/lib/contracts";
import { formatError, truncateAddress } from "@/lib/app-utils";

export function ConnectWallet() {
  const { address, isConnected, chainId: connectedChainId } = useConnection();

  const connect = useConnect();
  const connectors = useConnectors();
  const disconnect = useDisconnect();
  const {
    mutateAsync: switchChainAsync,
    isPending: isSwitching,
    error: switchError,
  } = useSwitchChain();

  const [menuOpen, setMenuOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const wrongChain = isConnected && connectedChainId !== chainId;

  const switchToXLayer = useCallback(async () => {
    try {
      await switchChainAsync({ chainId });
    } catch {
      // The mutation error is rendered below, so a rejected wallet request
      // does not create an unhandled promise rejection.
    }
  }, [switchChainAsync]);

  useEffect(() => {
    if (!menuOpen) return;

    function handleClickOutside(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    }

    function handleEscape(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setMenuOpen(false);
      }
    }

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("keydown", handleEscape);

    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleEscape);
    };
  }, [menuOpen]);

  const handleDisconnect = useCallback(() => {
    setMenuOpen(false);
    disconnect.mutate();
  }, [disconnect]);

  const handleCopy = useCallback(() => {
    if (!address) return;
    void navigator.clipboard
      .writeText(address)
      .then(() => {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => setCopied(false));
  }, [address]);

  if (isConnected && address) {
    return (
      <div className="app-connect-wrap" ref={menuRef}>
        <button
          type="button"
          className="app-connect connected"
          onClick={() => setMenuOpen((open) => !open)}
          aria-expanded={menuOpen}
          aria-haspopup="dialog"
        >
          {truncateAddress(address)}
        </button>

        {menuOpen && (
          <div className="app-connect-popover">
            <button
              type="button"
              className="app-connect-address"
              onClick={handleCopy}
              title="Copy wallet address"
            >
              {copied ? "Copied!" : address}
            </button>
            {wrongChain && (
              <button
                type="button"
                className="app-connect-disconnect"
                onClick={() => void switchToXLayer()}
                disabled={isSwitching}
              >
                {isSwitching
                  ? "Switching network…"
                  : "Switch to X Layer Testnet"}
              </button>
            )}
            {switchError && (
              <span className="app-connect-error">
                {formatError(switchError)}
              </span>
            )}
            <button
              type="button"
              className="app-connect-disconnect"
              onClick={handleDisconnect}
            >
              Disconnect
            </button>
          </div>
        )}
      </div>
    );
  }

  const connector = connectors[0];

  return (
    <div className="app-connect-wrap">
      <button
        type="button"
        className="app-connect"
        disabled={connect.isPending || !connector}
        onClick={() => {
          if (connector) {
            connect.mutate({ connector });
          }
        }}
      >
        {connect.isPending ? "Connecting…" : "Connect wallet"}
      </button>

      {connect.error && (
        <span className="app-connect-error">{formatError(connect.error)}</span>
      )}
    </div>
  );
}
