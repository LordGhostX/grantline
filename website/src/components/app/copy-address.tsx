"use client";

import { useState } from "react";
import { truncateAddress } from "@/lib/app-utils";

type Props = {
  address: string;
  label?: string;
};

export function CopyAddress({ address, label = "address" }: Props) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      setCopied(false);
    }
  }

  return (
    <button
      type="button"
      className="app-code app-copy-address"
      title={`Copy ${label}`}
      aria-label={`Copy ${label} ${address}`}
      onClick={handleCopy}
    >
      {copied ? "Copied" : truncateAddress(address)}
    </button>
  );
}
