"use client";

import "./v2.css";
import { useCallback, useEffect, useState } from "react";
import type {
  KeyboardEvent as ReactKeyboardEvent,
  MouseEvent as ReactMouseEvent,
} from "react";
import Link from "next/link";
import Lenis from "lenis";
import GrantlineMark from "@/components/grantline-mark";
import { repositoryUrl, xUrl } from "@/lib/site-links";

type DecisionKey = "allow" | "escalate" | "deny";

type DecisionCase = {
  action: string;
  amount: string;
  rows: readonly [string, string, string][];
  decision: string;
  tone: DecisionKey;
  reason: string;
  path: {
    fromLabel: string;
    fromTitle: string;
    fromDetail: string;
    toLabel: string;
    toTitle: string;
    toDetail: string;
  };
};

const decisionCases: Record<DecisionKey, DecisionCase> = {
  allow: {
    action: "Routine supplier payment",
    amount: "$2,500 · signed Action Plan",
    rows: [
      ["Mandate", "WITHIN BOUNDARY", "ok"],
      ["Preflight", "PASS", "ok"],
      ["Owner approval", "NOT REQUIRED", "muted"],
    ],
    decision: "ALLOW",
    tone: "allow",
    reason: "The proposal may enter the controlled execution path.",
    path: {
      fromLabel: "Authorised path",
      fromTitle: "Controlled execution",
      fromDetail: "The proposal may proceed.",
      toLabel: "Controlled capital",
      toTitle: "Vault",
      toDetail: "Owner custody remains intact.",
    },
  },
  escalate: {
    action: "Larger supplier payment",
    amount: "$12,000 · signed Action Plan",
    rows: [
      ["Mandate", "BOUNDARY CROSSED", "warn"],
      ["Preflight", "PASS", "ok"],
      ["Owner approval", "REQUIRED", "warn"],
    ],
    decision: "ESCALATE",
    tone: "escalate",
    reason: "Route the exact proposal to the owner for review.",
    path: {
      fromLabel: "Owner review",
      fromTitle: "Re-evaluate",
      fromDetail: "Approval does not bypass current checks.",
      toLabel: "Pending",
      toTitle: "No capital moves",
      toDetail: "Awaiting the next decision.",
    },
  },
  deny: {
    action: "Signed under revoked authority",
    amount: "$25,000 · signed Action Plan",
    rows: [
      ["Mandate", "INACTIVE", "bad"],
      ["Authority lineage", "REVOKED", "bad"],
      ["Execution", "NOT SUBMITTED", "muted"],
    ],
    decision: "DENY",
    tone: "deny",
    reason: "Stop before the proposal reaches the Vault.",
    path: {
      fromLabel: "Denied",
      fromTitle: "No execution",
      fromDetail: "The proposal stops here.",
      toLabel: "Controlled capital",
      toTitle: "Vault",
      toDetail: "Remains unchanged.",
    },
  },
};

const decisionKeys = Object.keys(decisionCases) as DecisionKey[];

export default function V2Page() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [activeCase, setActiveCase] = useState<DecisionKey>("allow");

  const closeMenu = useCallback(() => setMenuOpen(false), []);
  const handleNoop = (event: ReactMouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
  };

  useEffect(() => {
    const root = document.querySelector<HTMLElement>(".landing-v2");
    if (!root) return;

    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const nav = root.querySelector<HTMLElement>(".v2-nav-wrap nav");
    let lenis: Lenis | null = null;
    let rafId = 0;

    if (!reduceMotion) {
      lenis = new Lenis({
        duration: 1.05,
        smoothWheel: true,
        wheelMultiplier: 0.9,
        touchMultiplier: 1,
      });

      const raf = (time: number) => {
        lenis?.raf(time);
        rafId = requestAnimationFrame(raf);
      };

      rafId = requestAnimationFrame(raf);
    }

    const scrollToAnchor = (target: string) => {
      const element = root.querySelector<HTMLElement>(target);
      if (!element) return;
      closeMenu();

      const performScroll = () => {
        const navHeight = nav?.offsetHeight ?? 0;
        if (lenis) {
          lenis.scrollTo(element, { offset: -navHeight });
          return;
        }

        const top =
          element.getBoundingClientRect().top + window.scrollY - navHeight;
        window.scrollTo({
          top,
          behavior: reduceMotion ? "auto" : "smooth",
        });
      };

      requestAnimationFrame(() => requestAnimationFrame(performScroll));
    };

    const anchorLinks =
      root.querySelectorAll<HTMLAnchorElement>('a[href^="#"]');
    const anchorHandlers: Array<[HTMLAnchorElement, (event: Event) => void]> =
      [];

    anchorLinks.forEach((link) => {
      const handler = (event: Event) => {
        const target = link.getAttribute("href");
        if (!target || target === "#" || !root.querySelector(target)) return;
        event.preventDefault();
        scrollToAnchor(target);
      };

      link.addEventListener("click", handler);
      anchorHandlers.push([link, handler]);
    });

    const revealElements = root.querySelectorAll<HTMLElement>(".v2-reveal");
    let observer: IntersectionObserver | null = null;

    if ("IntersectionObserver" in window && !reduceMotion) {
      observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            entry.target.classList.add("is-visible");
            observer?.unobserve(entry.target);
          });
        },
        { threshold: 0.12 },
      );
      revealElements.forEach((element) => observer?.observe(element));
    } else {
      revealElements.forEach((element) => element.classList.add("is-visible"));
    }

    const onKeydown = (event: globalThis.KeyboardEvent) => {
      if (event.key === "Escape") closeMenu();
    };
    const onResize = () => {
      if (window.innerWidth > 760) closeMenu();
    };

    window.addEventListener("keydown", onKeydown);
    window.addEventListener("resize", onResize);

    return () => {
      lenis?.destroy();
      cancelAnimationFrame(rafId);
      observer?.disconnect();
      anchorHandlers.forEach(([link, handler]) => {
        link.removeEventListener("click", handler);
      });
      window.removeEventListener("keydown", onKeydown);
      window.removeEventListener("resize", onResize);
    };
  }, [closeMenu]);

  const current = decisionCases[activeCase];

  const handleDecisionKey = (
    event: ReactKeyboardEvent<HTMLButtonElement>,
    index: number,
  ) => {
    if (
      event.key !== "ArrowLeft" &&
      event.key !== "ArrowRight" &&
      event.key !== "Home" &&
      event.key !== "End"
    ) {
      return;
    }
    event.preventDefault();
    const nextIndex =
      event.key === "Home"
        ? 0
        : event.key === "End"
          ? decisionKeys.length - 1
          : (index +
              (event.key === "ArrowRight" ? 1 : -1) +
              decisionKeys.length) %
            decisionKeys.length;
    const next = decisionKeys[nextIndex];
    setActiveCase(next);
    event.currentTarget.parentElement
      ?.querySelector<HTMLButtonElement>(`[data-case="${next}"]`)
      ?.focus();
  };

  return (
    <div className="landing-v2">
      <div className="v2-page-grid" aria-hidden="true" />

      <div className="v2-nav-wrap">
        <nav className="v2-shell" aria-label="Preview navigation">
          <a className="v2-brand" href="#top" aria-label="Grantline home">
            <GrantlineMark className="v2-brand-mark" />
            <span>Grantline</span>
          </a>

          <div className="v2-nav-links">
            <a href="#how-it-works">How it works</a>
            <a href="#model">The Grantline model</a>
            <a href="#live">What&apos;s live</a>
            <Link href="/docs">Docs</Link>
            <a href={repositoryUrl} target="_blank" rel="noreferrer nofollow">
              GitHub <span aria-hidden="true">↗</span>
            </a>
            <a
              href="#"
              className="v2-btn v2-btn-primary v2-coming-soon"
              aria-disabled="true"
              onClick={handleNoop}
            >
              Demo coming soon
            </a>
          </div>

          <button
            className="v2-menu-toggle"
            type="button"
            aria-label={menuOpen ? "Close navigation" : "Open navigation"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((open) => !open)}
          >
            <span className="v2-menu-icon" aria-hidden="true">
              <span />
              <span />
              <span />
            </span>
          </button>
        </nav>

        <div className="v2-mobile-menu" data-open={menuOpen}>
          <div className="v2-mobile-menu-inner">
            <a href="#how-it-works" onClick={closeMenu}>
              How it works
            </a>
            <a href="#model" onClick={closeMenu}>
              The Grantline model
            </a>
            <a href="#live" onClick={closeMenu}>
              What&apos;s live
            </a>
            <Link href="/docs" onClick={closeMenu}>
              Documentation
            </Link>
            <a href={repositoryUrl} target="_blank" rel="noreferrer nofollow">
              GitHub <span aria-hidden="true">↗</span>
            </a>
            <a
              className="v2-mobile-demo"
              href="#"
              aria-disabled="true"
              onClick={(event) => {
                handleNoop(event);
                closeMenu();
              }}
            >
              Demo coming soon
            </a>
          </div>
        </div>
      </div>

      <main id="top">
        <header className="v2-hero">
          <div className="v2-shell v2-hero-grid">
            <div className="v2-reveal">
              <div className="v2-eyebrow">
                Financial authorisation for AI agents
              </div>
              <h1>
                Give AI agents authority to act without giving them unrestricted
                control.
              </h1>
              <p className="v2-hero-copy">
                Grantline sits between an AI agent&apos;s signed intent and
                execution. The agent proposes what it wants to do; Grantline
                checks whether its current authority permits it before
                controlled capital can move.
              </p>
              <div className="v2-principle">
                Your agent decides what to do. Grantline decides whether it is
                authorised.
              </div>
              <div className="v2-hero-actions">
                <a className="v2-btn v2-btn-primary" href="#how-it-works">
                  See how Grantline works
                </a>
                <Link className="v2-btn v2-btn-quiet" href="/docs">
                  Read the docs
                </Link>
              </div>
            </div>

            <div
              className="v2-hero-visual v2-reveal"
              aria-label="Illustrative Grantline authority path"
            >
              <div className="v2-visual-head">
                <span>Illustrative authority path</span>
                <span className="v2-status">BOUNDARY ACTIVE</span>
              </div>

              <div className="v2-path-top">
                <div className="v2-path-node">
                  <span className="v2-label">Your agent</span>
                  <strong>Chooses</strong>
                  <small>strategy and intent</small>
                </div>
                <span className="v2-path-arrow" aria-hidden="true">
                  →
                </span>
                <div className="v2-path-node">
                  <span className="v2-label">Signed proposal</span>
                  <strong>Action Plan</strong>
                  <small>exact intent</small>
                </div>
              </div>

              <div className="v2-gate">
                <div className="v2-gate-head">
                  <span>Grantline</span>
                  <span className="v2-mono-muted">CURRENT AUTHORITY</span>
                </div>
                <div
                  className="v2-decision-tabs"
                  role="tablist"
                  aria-label="Illustrative authorisation outcomes"
                >
                  {decisionKeys.map((key, index) => (
                    <button
                      key={key}
                      className="v2-decision-tab"
                      type="button"
                      role="tab"
                      id={`v2-decision-tab-${key}`}
                      aria-selected={activeCase === key}
                      aria-controls="v2-decision-panel"
                      tabIndex={activeCase === key ? 0 : -1}
                      data-case={key}
                      onClick={() => setActiveCase(key)}
                      onKeyDown={(event) => handleDecisionKey(event, index)}
                    >
                      {key === "allow"
                        ? "Allow"
                        : key === "escalate"
                          ? "Escalate"
                          : "Deny"}
                    </button>
                  ))}
                </div>
                <div className="v2-gate-body">
                  <div className="v2-request">
                    <span className="v2-label">Proposed action</span>
                    <strong>{current.action}</strong>
                    <small>{current.amount}</small>
                  </div>
                  <div className="v2-checks">
                    {current.rows.map(([label, value, tone]) => (
                      <div className="v2-check-row" key={label}>
                        <span>{label}</span>
                        <strong className={tone}>{value}</strong>
                      </div>
                    ))}
                  </div>
                  <div
                    id="v2-decision-panel"
                    role="tabpanel"
                    tabIndex={0}
                    aria-labelledby={`v2-decision-tab-${activeCase}`}
                    className={`v2-decision-output ${current.tone}`}
                    aria-live="polite"
                  >
                    <div>
                      <span className="v2-label">Decision</span>
                      <strong>{current.decision}</strong>
                    </div>
                    <p>{current.reason}</p>
                  </div>
                </div>
              </div>

              <div className={`v2-path-bottom v2-path-bottom-${current.tone}`}>
                <div className="v2-path-node v2-path-node-small">
                  <span className="v2-label">{current.path.fromLabel}</span>
                  <strong>{current.path.fromTitle}</strong>
                  <small>{current.path.fromDetail}</small>
                </div>
                <span className="v2-path-arrow" aria-hidden="true">
                  →
                </span>
                <div className="v2-path-node v2-path-node-small">
                  <span className="v2-label">{current.path.toLabel}</span>
                  <strong>{current.path.toTitle}</strong>
                  <small>{current.path.toDetail}</small>
                </div>
              </div>
              <p className="v2-visual-note">
                The agent signs intent. It never becomes the Vault authority.
              </p>
            </div>
          </div>
        </header>

        <section id="how-it-works">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">Where Grantline fits</div>
              <h2>Strategy. Authority. Execution.</h2>
              <p>
                Grantline owns the middle layer. It does not choose an
                agent&apos;s strategy or pretend that an authorisation result
                guarantees a downstream transaction will succeed.
              </p>
            </div>

            <div className="v2-role-grid v2-reveal">
              <article className="v2-role-card">
                <span className="v2-card-number">01</span>
                <div className="v2-card-kicker">Your agent</div>
                <h3>Chooses</h3>
                <p>
                  Models, workflows, and strategies determine what action the
                  agent wants to propose.
                </p>
                <strong>What should I do?</strong>
              </article>
              <article className="v2-role-card v2-role-card-accent">
                <span className="v2-card-number">02</span>
                <div className="v2-card-kicker">Grantline</div>
                <h3>Authorises</h3>
                <p>
                  Current Mandate authority and configured checks determine
                  whether the exact proposal may proceed.
                </p>
                <strong>Am I allowed to do it?</strong>
              </article>
              <article className="v2-role-card">
                <span className="v2-card-number">03</span>
                <div className="v2-card-kicker">Execution path</div>
                <h3>Executes</h3>
                <p>
                  The authorised path reaches controlled capital, while
                  downstream systems can still accept or reject the action.
                </p>
                <strong>Did it complete?</strong>
              </article>
            </div>
          </div>
        </section>

        <section className="v2-section-dark">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">Access is not authority</div>
              <h2>
                A signature proves who proposed an action. It does not grant
                Vault authority.
              </h2>
              <p>
                The signing key identifies the agent behind the proposal.
                Grantline evaluates that proposal separately, and the Vault only
                accepts calls from its configured execution authority.
              </p>
            </div>

            <div className="v2-access-frame v2-reveal">
              <div className="v2-access-step">
                <span className="v2-label">Agent identity</span>
                <strong>“This action came from Agent A.”</strong>
                <small>Signature proves intent.</small>
              </div>
              <span className="v2-access-arrow" aria-hidden="true">
                →
              </span>
              <div className="v2-access-step v2-access-step-accent">
                <span className="v2-label">Grantline</span>
                <strong>“Does Agent A have authority now?”</strong>
                <small>Current rules are evaluated.</small>
              </div>
              <span className="v2-access-arrow" aria-hidden="true">
                →
              </span>
              <div className="v2-access-step">
                <span className="v2-label">Vault boundary</span>
                <strong>“Only the authorised path can move capital.”</strong>
                <small>Owner custody remains separate.</small>
              </div>
            </div>
          </div>
        </section>

        <section id="use-cases">
          <div className="v2-shell">
            <div className="v2-use-case-layout">
              <div className="v2-section-head v2-reveal">
                <div className="v2-eyebrow">One agent. Bounded authority.</div>
                <h2>
                  Routine actions can run automatically. Boundary crossings
                  still have a path.
                </h2>
                <p>
                  A payments or operations agent can propose ordinary transfers
                  while the owner keeps a defined boundary around controlled
                  capital.
                </p>
              </div>

              <div className="v2-outcome-grid v2-reveal">
                <article className="v2-outcome-card v2-outcome-allow">
                  <span className="v2-label">Within authority</span>
                  <code>ALLOW</code>
                  <h3>Routine supplier payment</h3>
                  <p>The proposal may enter the controlled execution path.</p>
                </article>
                <article className="v2-outcome-card v2-outcome-escalate">
                  <span className="v2-label">Configured boundary crossed</span>
                  <code>ESCALATE</code>
                  <h3>Larger supplier payment</h3>
                  <p>Route the exact proposal to the owner for review.</p>
                </article>
                <article className="v2-outcome-card v2-outcome-deny">
                  <span className="v2-label">Authority no longer exists</span>
                  <code>DENY</code>
                  <h3>Signed under revoked authority</h3>
                  <p>Stop before the proposal reaches the Vault.</p>
                </article>
              </div>
            </div>
          </div>
        </section>

        <section className="v2-section-dark">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">The authorisation path</div>
              <h2>Every action starts as a proposal.</h2>
              <p>
                An <code className="v2-inline-allow">ALLOW</code> result means
                the proposal may enter the execution path. It does not mean that
                an external protocol has already accepted it.
              </p>
            </div>

            <div className="v2-flow v2-reveal">
              <div className="v2-flow-step">
                <span>01</span>
                <strong>Intent</strong>
                <p>The agent decides what it wants to do.</p>
              </div>
              <div className="v2-flow-step">
                <span>02</span>
                <strong>Signed proposal</strong>
                <p>The exact intent becomes an Action Plan.</p>
              </div>
              <div className="v2-flow-step v2-flow-control">
                <span>03</span>
                <strong>Authority check</strong>
                <p>Current Mandate and active lineage are evaluated.</p>
              </div>
              <div className="v2-flow-step v2-flow-control">
                <span>04</span>
                <strong>Decision</strong>
                <p>
                  <code className="v2-code-allow">ALLOW</code>,{" "}
                  <code className="v2-code-escalate">ESCALATE</code>, or{" "}
                  <code className="v2-code-deny">DENY</code>.
                </p>
              </div>
              <div className="v2-flow-step v2-flow-control">
                <span>05</span>
                <strong>Escalation re-check</strong>
                <p>
                  For escalated proposals, approval does not skip current
                  checks.
                </p>
              </div>
              <div className="v2-flow-step">
                <span>06</span>
                <strong>Controlled execution</strong>
                <p>Only the authorised path can reach the Vault.</p>
              </div>
            </div>

            <div
              className="v2-branch v2-reveal"
              aria-label="Authorisation outcomes"
            >
              <div>
                <code>ALLOW</code>
                <span>→</span>
                <strong>Execute</strong>
              </div>
              <div>
                <code>ESCALATE</code>
                <span>→</span>
                <strong>Owner review → re-evaluate</strong>
              </div>
              <div>
                <code>DENY</code>
                <span>→</span>
                <strong>Stop</strong>
              </div>
            </div>
          </div>
        </section>

        <section id="model">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">The Grantline model</div>
              <h2>Four things make bounded agent authority possible.</h2>
              <p>
                The core model stays compact. Delegation, Preflight, escalation,
                and revocation add control around it without turning a signing
                key into unrestricted custody.
              </p>
            </div>

            <div className="v2-model-grid v2-reveal">
              <article className="v2-model-card">
                <span className="v2-card-number">01 / AUTHORITY</span>
                <h3>Mandate</h3>
                <p>
                  Defines the authority an agent may exercise against controlled
                  capital.
                </p>
              </article>
              <article className="v2-model-card">
                <span className="v2-card-number">02 / INTENT</span>
                <h3>Action Plan</h3>
                <p>
                  Captures the exact structured proposal that the agent signs.
                </p>
              </article>
              <article className="v2-model-card">
                <span className="v2-card-number">03 / CUSTODY</span>
                <h3>Vault</h3>
                <p>
                  Holds the controlled capital while the owner retains custody
                  and administration.
                </p>
              </article>
              <article className="v2-model-card v2-model-card-accent">
                <span className="v2-card-number">04 / AUTHORISATION</span>
                <h3>Decision</h3>
                <p>
                  Resolves what Grantline permits next:{" "}
                  <code className="v2-code-allow">ALLOW</code>,{" "}
                  <code className="v2-code-escalate">ESCALATE</code>, or{" "}
                  <code className="v2-code-deny">DENY</code>.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section className="v2-section-dark" id="authority-state">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">Current authority</div>
              <h2>Permission is checked when it matters.</h2>
              <p>
                A signature does not freeze historical permissions. Grantline
                reads current authority when the proposal is evaluated and again
                when an approved escalation is executed.
              </p>
            </div>

            <div className="v2-state-grid v2-reveal">
              <article>
                <span className="v2-label">Rules can tighten</span>
                <h3>Older intent can meet newer limits.</h3>
                <p>
                  A proposal signed under a wider boundary can stop when the
                  Mandate becomes more restrictive.
                </p>
              </article>
              <article>
                <span className="v2-label">Authority can be revoked</span>
                <h3>History remains. Future use stops.</h3>
                <p>
                  Revocation preserves the lineage while preventing an inactive
                  Mandate or ancestor from authorising new execution.
                </p>
              </article>
              <article>
                <span className="v2-label">Approval is not a bypass</span>
                <h3>Owner review still meets current state.</h3>
                <p>
                  An approved escalation is checked again before capital moves,
                  so changed authority can still stop it.
                </p>
              </article>
            </div>

            <div className="v2-delegation v2-reveal">
              <div>
                <div className="v2-eyebrow">Delegated authority</div>
                <h2>Authority can move down. It cannot expand on the way.</h2>
                <p>
                  A sub-agent receives a narrower portion of the authority above
                  it. Its effective authority is the current Mandate intersected
                  with the active boundaries in its lineage.
                </p>
                <div className="v2-formula">
                  effective authority = current Mandate &cap; active ancestor
                  boundaries
                </div>
              </div>

              <div
                className="v2-lineage"
                aria-label="Illustrative delegated authority lineage"
              >
                <div className="v2-lineage-card">
                  <strong>Owner</strong>
                  <small>source of authority</small>
                </div>
                <span className="v2-lineage-line" aria-hidden="true">
                  <span>→</span>
                </span>
                <div className="v2-lineage-card v2-lineage-card-accent">
                  <strong>Treasury agent</strong>
                  <small>bounded operating authority</small>
                </div>
                <span className="v2-lineage-line" aria-hidden="true">
                  <span>→</span>
                </span>
                <div className="v2-lineage-card">
                  <strong>Sub-agent</strong>
                  <small>narrower execution authority</small>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section>
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">Conditional authority</div>
              <h2>Authority can be conditional without becoming vague.</h2>
              <p>
                Each layer answers a different question about whether an action
                may proceed, so the owner can keep routine execution automatic
                without treating every boundary as a hard stop.
              </p>
            </div>

            <div className="v2-condition-grid v2-reveal">
              <article>
                <span className="v2-label">Mandate rules</span>
                <h3>Is the proposal within the authority granted?</h3>
                <p>
                  Limits, permitted actions, delegation rights, and current
                  lineage define the hard boundary.
                </p>
              </article>
              <article>
                <span className="v2-label">Preflight</span>
                <h3>Would the resulting Vault state remain safe?</h3>
                <p>
                  The current MVP checks the projected native Vault balance
                  against an inherited reserve boundary.
                </p>
              </article>
              <article>
                <span className="v2-label">Escalation</span>
                <h3>Does this configured boundary need owner review?</h3>
                <p>
                  The owner approves or denies the exact stored proposal, and
                  execution checks current state again.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section id="live" className="v2-section-dark">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">Live on testnet</div>
              <h2>The core authority loop is already enforced onchain.</h2>
              <p>
                The current X Layer testnet MVP proves the contract-backed path
                from a signed proposal to bounded execution, including the cases
                where authority or execution must stop.
              </p>
            </div>

            <div className="v2-live-layout">
              <ul className="v2-capability-list v2-reveal">
                <li>Vault custody and controlled execution</li>
                <li>Typed Action Plans with EIP-712 signatures</li>
                <li>Active Mandates and inherited authority</li>
                <li>
                  <code className="v2-code-allow">ALLOW</code>,{" "}
                  <code className="v2-code-escalate">ESCALATE</code>, and{" "}
                  <code className="v2-code-deny">DENY</code> evaluation
                </li>
                <li>Native amount limits and native-balance Preflight</li>
                <li>Owner-approved escalation and re-evaluation</li>
                <li>Delegation, revocation, and replay protection</li>
                <li>Committed onchain execution evidence</li>
              </ul>

              <div className="v2-proof-card v2-reveal">
                <div className="v2-proof-head">
                  <span>Inspect the enforcement</span>
                  <span className="v2-status">X LAYER TESTNET</span>
                </div>
                <div className="v2-proof-links">
                  <a
                    href={`${repositoryUrl}/tree/main/contracts`}
                    target="_blank"
                    rel="noreferrer nofollow"
                  >
                    <strong>View the contracts</strong>
                    <span>See the deployed implementation and manifest.</span>
                    <span className="v2-link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </a>
                  <Link href="/docs/enforcement/security-model">
                    <strong>Read how enforcement works</strong>
                    <span>
                      Follow the boundary from agent intent to Vault custody.
                    </span>
                    <span className="v2-link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </Link>
                  <Link href="/docs/execution/networks/x-layer-testnet">
                    <strong>Inspect testnet evidence</strong>
                    <span>
                      Review the current network and exercised integration.
                    </span>
                    <span className="v2-link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </Link>
                  <a
                    href="#"
                    className="v2-proof-link-disabled v2-coming-soon"
                    aria-disabled="true"
                    onClick={handleNoop}
                  >
                    <strong>Try the demo</strong>
                    <span>Demo coming soon.</span>
                    <span className="v2-link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </a>
                </div>
                <p className="v2-proof-note">
                  Committed authority changes, approvals, custody changes, and
                  successful execution events are traceable onchain. A read-only
                  <code> DENY</code> returns without creating a state change.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section id="vision">
          <div className="v2-shell">
            <div className="v2-section-head v2-reveal">
              <div className="v2-eyebrow">Where Grantline goes next</div>
              <h2>
                Make authority more expressive without weakening the boundary.
              </h2>
              <p>
                The interface around Grantline can expand while the underlying
                model stays stable: an agent proposes, authority is evaluated,
                and only an authorised path may act on controlled capital.
              </p>
            </div>

            <div className="v2-future-grid v2-reveal">
              <article>
                <span className="v2-label">Richer authority</span>
                <h3>More precise Mandates</h3>
                <p>
                  Pausing, validity windows, destination and capability
                  policies, and shared authority budgets.
                </p>
              </article>
              <article>
                <span className="v2-label">External conditions</span>
                <h3>Guardians</h3>
                <p>
                  Planned conditions that can bring selected, attributable, and
                  time-bounded external context into authorisation.
                </p>
              </article>
              <article>
                <span className="v2-label">Integration</span>
                <h3>Easier adoption</h3>
                <p>
                  SDK and API surfaces around the same underlying contract
                  authority model.
                </p>
              </article>
              <article>
                <span className="v2-label">Decision evidence</span>
                <h3>Clearer records</h3>
                <p>
                  Indexing and assembled Decision Receipts that connect
                  proposals, authority, approval, and execution.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section className="v2-cta">
          <div className="v2-shell v2-reveal">
            <div className="v2-cta-brand">
              <GrantlineMark className="v2-brand-mark" />
              <span>Grantline</span>
            </div>
            <h2>Let agents act. Keep authority bounded.</h2>
            <p>
              Give autonomous systems room to operate without turning their
              signing keys into unrestricted control over capital.
            </p>
            <div className="v2-cta-actions">
              <a
                href="#"
                className="v2-btn v2-btn-primary v2-coming-soon"
                aria-disabled="true"
                onClick={handleNoop}
              >
                Demo coming soon
              </a>
              <Link className="v2-btn v2-btn-quiet" href="/docs">
                Read the documentation
              </Link>
              <a
                className="v2-btn v2-btn-quiet"
                href={`${repositoryUrl}/tree/main/contracts`}
                target="_blank"
                rel="noreferrer nofollow"
              >
                View the contracts <span aria-hidden="true">↗</span>
              </a>
            </div>
          </div>
        </section>
      </main>

      <footer className="v2-footer">
        <div className="v2-shell v2-footer-row">
          <a className="v2-brand" href="#top" aria-label="Grantline home">
            <GrantlineMark className="v2-brand-mark" />
            <span>Grantline</span>
          </a>
          <div className="v2-footer-links">
            <Link href="/docs">Documentation</Link>
            <a href={repositoryUrl} target="_blank" rel="noreferrer nofollow">
              GitHub ↗
            </a>
            <a href={xUrl} target="_blank" rel="noreferrer nofollow">
              X / @usegrantline ↗
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
