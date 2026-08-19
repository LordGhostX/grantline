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

export function ConnectWallet() {
  const { address, isConnected, chain } = useConnection();

  const connect = useConnect();
  const connectors = useConnectors();
  const disconnect = useDisconnect();
  const { switchChain } = useSwitchChain();

  const [menuOpen, setMenuOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const wrongChain = isConnected && chain && chain.id !== chainId;

  const switchToXLayer = useCallback(() => {
    switchChain({ chainId });
  }, [switchChain]);

  useEffect(() => {
    if (wrongChain) switchToXLayer();
  }, [wrongChain, switchToXLayer]);

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
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, [address]);

  if (isConnected && address) {
    return (
      <div className="app-connect-wrap" ref={menuRef}>
        <button
          type="button"
          className="app-connect connected"
          onClick={() => setMenuOpen((open) => !open)}
        >
          <span className="app-connect-dot" />
          {address.slice(0, 6)}…{address.slice(-4)}
        </button>

        {menuOpen && (
          <div className="app-connect-popover">
            <span
              className="app-connect-address"
              style={{ cursor: "pointer" }}
              onClick={handleCopy}
            >
              {copied ? "Copied!" : address}
            </span>
            {wrongChain && (
              <button
                type="button"
                className="app-connect-disconnect"
                onClick={switchToXLayer}
              >
                Switch to X Layer Testnet
              </button>
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
        <span className="app-connect-error">
          {"shortMessage" in connect.error
            ? String(connect.error.shortMessage)
            : connect.error.message}
        </span>
      )}
    </div>
  );
}
