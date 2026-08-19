"use client";

import { useState, useCallback } from "react";
import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { ConnectWallet } from "./connect-wallet";
import GrantlineMark from "@/components/grantline-mark";
import { repositoryUrl } from "@/lib/site-links";

type Props = {
  children: ReactNode;
};

const appNavItems = [
  { href: "/app", label: "Dashboard", exact: true },
  { href: "/app/vaults", label: "Vaults" },
  { href: "/app/mandates", label: "Mandates" },
  { href: "/app/authority", label: "Authority" },
  { href: "/app/execute", label: "Execute" },
  { href: "/app/escalations", label: "Escalations" },
  { href: "/app/activity", label: "Activity" },
];

export function Sidebar({ children }: Props) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  const closeMobile = useCallback(() => setMobileOpen(false), []);

  return (
    <div className="app-layout">
      <div
        className={`app-backdrop${mobileOpen ? " open" : ""}`}
        onClick={closeMobile}
      />

      <aside className="app-sidebar" data-open={mobileOpen}>
        <div className="app-sidebar-top">
          <Link href="/app" className="app-brand" onClick={closeMobile}>
            <GrantlineMark
              className="app-brand-mark"
              style={{ color: "var(--brand, #d0b46c)" }}
            />
            <span>Grantline</span>
          </Link>

          <nav className="app-nav">
            {appNavItems.map((item) => {
              const active = item.exact
                ? pathname === item.href
                : pathname.startsWith(item.href);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`app-nav-item${active ? " active" : ""}`}
                  onClick={closeMobile}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
        </div>

        <div className="app-sidebar-bottom">
          <Link
            href="/"
            className={`app-nav-item${pathname === "/" ? " active" : ""}`}
            onClick={closeMobile}
          >
            Home
          </Link>
          <a
            href="/docs"
            className="app-nav-item"
            target="_blank"
            rel="noreferrer"
          >
            Docs ↗
          </a>
          <a
            href={repositoryUrl}
            className="app-nav-item"
            target="_blank"
            rel="noreferrer nofollow"
          >
            GitHub ↗
          </a>
        </div>
      </aside>

      <div className="app-main">
        <header className="app-topbar">
          <button
            type="button"
            className="app-menu-toggle"
            onClick={() => setMobileOpen(true)}
            aria-label="Open menu"
          >
            <span className="app-menu-icon" aria-hidden="true">
              <span />
              <span />
              <span />
            </span>
          </button>
          <div className="app-topbar-right">
            <div className="app-network">
              <span className="app-network-dot" />
              X Layer Testnet
            </div>
            <ConnectWallet />
          </div>
        </header>
        <div className="app-content">{children}</div>
      </div>
    </div>
  );
}
