"use client";

import { useState, useCallback, useEffect } from "react";
import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { ConnectWallet } from "./connect-wallet";
import { NetworkStatus } from "./network-status";
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

  useEffect(() => {
    if (!mobileOpen) return;

    function handleEscape(event: KeyboardEvent) {
      if (event.key === "Escape") closeMobile();
    }

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", handleEscape);

    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", handleEscape);
    };
  }, [closeMobile, mobileOpen]);

  return (
    <div className="app-layout">
      <div
        className={`app-backdrop${mobileOpen ? " open" : ""}`}
        onClick={closeMobile}
      />

      <aside id="app-sidebar" className="app-sidebar" data-open={mobileOpen}>
        <div className="app-sidebar-top">
          <Link href="/app" className="app-brand" onClick={closeMobile}>
            <GrantlineMark className="app-brand-mark" />
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
                  aria-current={active ? "page" : undefined}
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
            aria-current={pathname === "/" ? "page" : undefined}
            onClick={closeMobile}
          >
            Home
          </Link>
          <Link
            href="/docs"
            className="app-nav-item"
            target="_blank"
            rel="noreferrer"
            onClick={closeMobile}
          >
            Docs ↗
          </Link>
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
            aria-controls="app-sidebar"
            aria-expanded={mobileOpen}
          >
            <span className="app-menu-icon" aria-hidden="true">
              <span />
              <span />
              <span />
            </span>
          </button>
          <div className="app-topbar-right">
            <NetworkStatus />
            <ConnectWallet />
          </div>
        </header>
        <div className="app-content">{children}</div>
      </div>
    </div>
  );
}
