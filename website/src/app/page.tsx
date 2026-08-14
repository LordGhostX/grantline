"use client";

import "./landing.css";
import { useCallback, useEffect, useState } from "react";
import type { KeyboardEvent as ReactKeyboardEvent } from "react";
import Link from "next/link";
import Lenis from "lenis";
import GrantlineMark from "@/components/grantline-mark";
import { repositoryUrl, xUrl } from "@/lib/site-links";

type DecisionKey = "allow" | "escalate" | "deny";

type DecisionCase = {
  action: string;
  amount: string;
  decision: string;
  tone: DecisionKey;
  reason: string;
};

const decisionCases: Record<DecisionKey, DecisionCase> = {
  allow: {
    action: "Routine supplier payment",
    amount: "$2,500 · signed Action Plan",
    decision: "ALLOW",
    tone: "allow",
    reason: "The proposal may enter the controlled execution path.",
  },
  escalate: {
    action: "Larger supplier payment",
    amount: "$12,000 · signed Action Plan",
    decision: "ESCALATE",
    tone: "escalate",
    reason: "Route the exact proposal to the owner for review.",
  },
  deny: {
    action: "Signed under revoked authority",
    amount: "$25,000 · signed Action Plan",
    decision: "DENY",
    tone: "deny",
    reason: "Stop before the proposal reaches the Vault.",
  },
};

const decisionKeys = Object.keys(decisionCases) as DecisionKey[];

export default function Home() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [activeCase, setActiveCase] = useState<DecisionKey>("allow");

  const closeMenu = useCallback(() => setMenuOpen(false), []);

  useEffect(() => {
    const root = document.querySelector<HTMLElement>(".landing");
    if (!root) return;

    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const nav = root.querySelector<HTMLElement>(".nav-wrap nav");
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

    const scrollToAnchor = (target: string, link?: HTMLAnchorElement) => {
      const element = root.querySelector<HTMLElement>(target);
      if (!element) return;
      closeMenu();

      const performScroll = () => {
        const navHeight = nav?.offsetHeight ?? 0;
        if (lenis) {
          lenis.scrollTo(element, { offset: -navHeight });
        } else {
          const top =
            element.getBoundingClientRect().top + window.scrollY - navHeight;
          window.scrollTo({
            top,
            behavior: reduceMotion ? "auto" : "smooth",
          });
        }

        if (link?.classList.contains("skip-link")) {
          element.focus({ preventScroll: true });
        }
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
        scrollToAnchor(target, link);
      };

      link.addEventListener("click", handler);
      anchorHandlers.push([link, handler]);
    });

    const revealElements = root.querySelectorAll<HTMLElement>(".reveal");
    let observer: IntersectionObserver | null = null;

    if ("IntersectionObserver" in window && !reduceMotion) {
      const viewportHeight = window.innerHeight;
      revealElements.forEach((element) => {
        const rect = element.getBoundingClientRect();
        if (rect.top < viewportHeight && rect.bottom > 0) {
          element.classList.add("is-visible");
        }
      });

      root.classList.add("motion-ready");
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
      revealElements.forEach((element) => {
        if (!element.classList.contains("is-visible")) {
          observer?.observe(element);
        }
      });
    } else {
      revealElements.forEach((element) => element.classList.add("is-visible"));
    }

    const onKeydown = (event: globalThis.KeyboardEvent) => {
      if (event.key === "Escape") closeMenu();
    };
    const onResize = () => {
      if (window.innerWidth > 960) closeMenu();
    };

    window.addEventListener("keydown", onKeydown);
    window.addEventListener("resize", onResize);

    return () => {
      lenis?.destroy();
      cancelAnimationFrame(rafId);
      observer?.disconnect();
      root.classList.remove("motion-ready");
      revealElements.forEach((element) =>
        element.classList.remove("is-visible"),
      );
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
    <div className="landing">
      <div className="page-grid" aria-hidden="true" />
      <a className="skip-link" href="#top">
        Skip to content
      </a>

      <div className="nav-wrap">
        <nav className="shell" aria-label="Primary navigation">
          <a className="brand" href="#top" aria-label="Grantline home">
            <GrantlineMark className="brand-mark" />
            <span>Grantline</span>
          </a>

          <div className="nav-links">
            <a href="#how-it-works">How it works</a>
            <a href="#live">What&apos;s live</a>
            <a href="#model">Authority model</a>
            <Link href="/docs">Docs</Link>
            <a href={repositoryUrl} target="_blank" rel="noreferrer nofollow">
              GitHub <span aria-hidden="true">↗</span>
            </a>
            <button
              type="button"
              className="btn btn-primary coming-soon"
              disabled
            >
              Demo coming soon
            </button>
          </div>

          <button
            className="menu-toggle"
            type="button"
            aria-label={menuOpen ? "Close navigation" : "Open navigation"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((open) => !open)}
          >
            <span className="menu-icon" aria-hidden="true">
              <span />
              <span />
              <span />
            </span>
          </button>
        </nav>

        <div className="mobile-menu" data-open={menuOpen}>
          <div className="mobile-menu-inner">
            <a href="#how-it-works" onClick={closeMenu}>
              How it works
            </a>
            <a href="#live" onClick={closeMenu}>
              What&apos;s live
            </a>
            <a href="#model" onClick={closeMenu}>
              Authority model
            </a>
            <Link href="/docs" onClick={closeMenu}>
              Documentation
            </Link>
            <a href={repositoryUrl} target="_blank" rel="noreferrer nofollow">
              GitHub <span aria-hidden="true">↗</span>
            </a>
            <button type="button" className="mobile-demo" disabled>
              Demo coming soon
            </button>
          </div>
        </div>
      </div>

      <main id="top" tabIndex={-1}>
        <header className="hero">
          <div className="shell hero-grid">
            <div className="reveal">
              <div className="eyebrow">
                Financial authorisation for AI agents
              </div>
              <h1>
                Let AI agents use capital without giving them unrestricted
                control.
              </h1>
              <p className="hero-copy">
                Grantline sits between an AI agent&apos;s signed intent and
                execution. The agent proposes what it wants to do; Grantline
                checks whether its current authority permits it before
                controlled capital can move.
              </p>
              <div className="principle">
                Your agent decides what to do. Grantline decides whether it is
                authorised.
              </div>
              <div className="hero-actions">
                <a className="btn btn-primary" href="#how-it-works">
                  See how Grantline works
                </a>
                <Link className="btn btn-quiet" href="/docs">
                  Read the docs
                </Link>
              </div>
            </div>

            <figure
              className="hero-visual reveal"
              aria-labelledby="visual-caption"
            >
              <figcaption id="visual-caption" className="visual-head">
                <span>Illustrative authority path</span>
                <span className="status">ILLUSTRATIVE OUTCOME</span>
              </figcaption>

              <div className="path-top">
                <div className="path-node">
                  <span className="label">Your agent</span>
                  <strong>Chooses</strong>
                  <small>strategy and intent</small>
                </div>
                <span className="path-arrow" aria-hidden="true">
                  →
                </span>
                <div className="path-node">
                  <span className="label">Signed proposal</span>
                  <strong>Action Plan</strong>
                  <small>exact intent</small>
                </div>
              </div>

              <div className="gate">
                <div className="gate-head">
                  <span className="gate-prompt">
                    <span>Explore outcomes</span>
                    <span className="gate-prompt-divider" aria-hidden="true">
                      ·
                    </span>
                    <span className="gate-prompt-instruction">
                      Select a decision state
                    </span>
                  </span>
                </div>
                <div
                  className="decision-tabs"
                  role="tablist"
                  aria-label="Illustrative authorisation outcomes"
                >
                  {decisionKeys.map((key, index) => (
                    <button
                      key={key}
                      className="decision-tab"
                      type="button"
                      role="tab"
                      id={`decision-tab-${key}`}
                      aria-selected={activeCase === key}
                      aria-controls="decision-panel"
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
                <div className="gate-body">
                  <div className="request">
                    <span className="label">Proposed action</span>
                    <strong>{current.action}</strong>
                    <small>{current.amount}</small>
                  </div>
                  <div
                    id="decision-panel"
                    role="tabpanel"
                    tabIndex={0}
                    aria-labelledby={`decision-tab-${activeCase}`}
                    className={`decision-output ${current.tone}`}
                    aria-live="polite"
                  >
                    <div>
                      <span className="label">Decision</span>
                      <strong>{current.decision}</strong>
                    </div>
                    <p>{current.reason}</p>
                  </div>
                </div>
              </div>
            </figure>
          </div>
        </header>

        <section id="how-it-works">
          <div className="shell">
            <div className="section-head reveal">
              <h2>Strategy. Authority. Execution.</h2>
              <p>
                Grantline owns the middle layer. It does not choose an
                agent&apos;s strategy or pretend that an authorisation result
                guarantees a downstream transaction will succeed.
              </p>
            </div>

            <div className="role-grid reveal">
              <article className="role-card">
                <span className="card-number">01</span>
                <div className="card-kicker">Your agent</div>
                <h3>Chooses</h3>
                <p>
                  Models, workflows, and strategies determine what action the
                  agent wants to propose.
                </p>
                <strong>What should I do?</strong>
              </article>
              <article className="role-card role-card-accent">
                <span className="card-number">02</span>
                <div className="card-kicker">Grantline</div>
                <h3>Authorises</h3>
                <p>
                  Current Mandate authority and configured checks determine
                  whether the exact proposal may proceed.
                </p>
                <strong>Am I allowed to do it?</strong>
              </article>
              <article className="role-card">
                <span className="card-number">03</span>
                <div className="card-kicker">Execution path</div>
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

        <section className="section-dark">
          <div className="shell">
            <div className="section-head reveal">
              <h2>A signature proves intent. Grantline defines authority.</h2>
              <p>
                The signing key identifies the agent behind the proposal.
                Grantline evaluates that proposal separately, and the Vault only
                accepts calls from its configured execution authority.
              </p>
            </div>

            <div className="access-frame reveal">
              <div className="access-step">
                <span className="label">Agent identity</span>
                <strong>“This action came from Agent A.”</strong>
                <small>Signature proves intent.</small>
              </div>
              <span className="access-arrow" aria-hidden="true">
                →
              </span>
              <div className="access-step access-step-accent">
                <span className="label">Grantline</span>
                <strong>“Does Agent A have authority now?”</strong>
                <small>Current rules are evaluated.</small>
              </div>
              <span className="access-arrow" aria-hidden="true">
                →
              </span>
              <div className="access-step">
                <span className="label">Vault boundary</span>
                <strong>“Only the authorised path can move capital.”</strong>
                <small>Owner custody remains separate.</small>
              </div>
            </div>
          </div>
        </section>

        <section id="where-it-fits">
          <div className="shell">
            <div className="section-head reveal">
              <h2>The agent can change. The authority model stays the same.</h2>
              <p>
                Give different agents room to operate inside a defined boundary
                while the owner keeps control of the capital.
              </p>
            </div>

            <div className="use-case-grid reveal">
              <article className="use-case-card">
                <span className="label">Payments agents</span>
                <h3>Routine payments</h3>
                <p>
                  Run ordinary transfers inside a defined boundary, with larger
                  actions routed for review.
                </p>
              </article>
              <article className="use-case-card">
                <span className="label">Treasury operations</span>
                <h3>Controlled capital movement</h3>
                <p>
                  Give an agent room to move capital without giving it
                  unrestricted custody.
                </p>
              </article>
              <article className="use-case-card">
                <span className="label">Operational agents</span>
                <h3>Automated workflows</h3>
                <p>
                  Connect recurring workflows to a defined capital pool while
                  owner control remains intact.
                </p>
              </article>
              <article className="use-case-card">
                <span className="label">Agent teams</span>
                <h3>Narrower authority</h3>
                <p>
                  Delegate specialised authority to sub-agents without losing
                  the lineage above them.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section id="live" className="section-dark">
          <div className="shell">
            <div className="section-head reveal">
              <div className="eyebrow">Live on testnet</div>
              <h2>The current X Layer testnet enforces the authority path.</h2>
              <p>
                The implementation covers signed proposals, inherited authority,
                owner escalation, revocation, and committed execution evidence.
              </p>
            </div>

            <div className="live-layout">
              <ul className="capability-list reveal">
                <li>Vault custody and controlled execution</li>
                <li>Typed Action Plans with EIP-712 signatures</li>
                <li>Active Mandates and inherited authority</li>
                <li>
                  <code className="code-allow">ALLOW</code>,{" "}
                  <code className="code-escalate">ESCALATE</code>, and{" "}
                  <code className="code-deny">DENY</code> evaluation
                </li>
                <li>Native amount limits and native-balance Preflight</li>
                <li>Owner-approved escalation and re-evaluation</li>
                <li>Delegation, revocation, and replay protection</li>
                <li>Committed onchain execution evidence</li>
              </ul>

              <div className="proof-card reveal">
                <div className="proof-head">
                  <span>Inspect the enforcement</span>
                  <span className="status">X LAYER TESTNET</span>
                </div>
                <div className="proof-links">
                  <a
                    href={`${repositoryUrl}/tree/main/contracts`}
                    target="_blank"
                    rel="noreferrer nofollow"
                  >
                    <strong>View the contracts</strong>
                    <span>See the deployed implementation and manifest.</span>
                    <span className="link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </a>
                  <Link href="/docs/enforcement/security-model">
                    <strong>Read how enforcement works</strong>
                    <span>
                      Follow the boundary from agent intent to Vault custody.
                    </span>
                    <span className="link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </Link>
                  <Link href="/docs/execution/networks/x-layer-testnet">
                    <strong>Inspect testnet evidence</strong>
                    <span>
                      Review the current network and exercised integration.
                    </span>
                    <span className="link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </Link>
                  <button
                    type="button"
                    className="proof-link-disabled coming-soon"
                    disabled
                  >
                    <strong>Try the demo</strong>
                    <span>Demo coming soon.</span>
                    <span className="link-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </button>
                </div>
                <p className="proof-note">
                  Committed authority changes, approvals, custody changes, and
                  successful execution events are traceable onchain. A read-only{" "}
                  <code className="code-deny">DENY</code> has no state change to
                  record.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="section-dark">
          <div className="shell">
            <div className="section-head reveal">
              <div className="eyebrow">The authorisation path</div>
              <h2>Every action starts as a proposal.</h2>
              <p>
                An <code className="inline-allow">ALLOW</code> result means the
                proposal may enter the execution path. It does not mean that an
                external protocol has already accepted it.
              </p>
            </div>

            <div className="flow reveal">
              <div className="flow-step">
                <span>01</span>
                <strong>Intent</strong>
                <p>The agent decides what it wants to do.</p>
              </div>
              <div className="flow-step">
                <span>02</span>
                <strong>Signed proposal</strong>
                <p>The exact intent becomes an Action Plan.</p>
              </div>
              <div className="flow-step flow-control">
                <span>03</span>
                <strong>Authority check</strong>
                <p>Current Mandate and active lineage are evaluated.</p>
              </div>
              <div className="flow-step flow-control">
                <span>04</span>
                <strong>Decision</strong>
                <p>
                  <code className="code-allow">ALLOW</code>,{" "}
                  <code className="code-escalate">ESCALATE</code>, or{" "}
                  <code className="code-deny">DENY</code>.
                </p>
              </div>
            </div>

            <div className="branch reveal" aria-label="Authorisation outcomes">
              <div>
                <code>ALLOW</code>
                <span>→</span>
                <strong>Controlled execution</strong>
              </div>
              <div>
                <code>ESCALATE</code>
                <span>→</span>
                <strong>Owner approval → re-evaluate → execute or stop</strong>
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
          <div className="shell">
            <div className="section-head reveal">
              <h2>Four concepts form Grantline&apos;s core authority model.</h2>
              <p>
                Delegation, Preflight, escalation, and revocation add controls
                around this model while the signing key never becomes
                unrestricted custody.
              </p>
            </div>

            <div className="model-grid reveal">
              <article className="model-card">
                <span className="card-number">01 / AUTHORITY</span>
                <h3>Mandate</h3>
                <p>
                  Defines the authority an agent may exercise against controlled
                  capital.
                </p>
              </article>
              <article className="model-card">
                <span className="card-number">02 / INTENT</span>
                <h3>Action Plan</h3>
                <p>
                  Captures the exact structured proposal that the agent signs.
                </p>
              </article>
              <article className="model-card">
                <span className="card-number">03 / CUSTODY</span>
                <h3>Vault</h3>
                <p>
                  Holds the controlled capital while the owner retains custody
                  and administration.
                </p>
              </article>
              <article className="model-card model-card-accent">
                <span className="card-number">04 / AUTHORISATION</span>
                <h3>Decision</h3>
                <p>
                  Resolves what Grantline permits next:{" "}
                  <code className="code-allow">ALLOW</code>,{" "}
                  <code className="code-escalate">ESCALATE</code>, or{" "}
                  <code className="code-deny">DENY</code>.
                </p>
              </article>
            </div>
            <div className="model-followup reveal">
              <h3>
                Before execution, Grantline checks authority and Vault state.
              </h3>
              <p>
                Mandate rules define authority. Preflight checks the projected
                Vault state. Escalation routes a configured boundary crossing to
                owner review.
              </p>
            </div>

            <div className="condition-grid reveal">
              <article>
                <span className="label">Mandate rules</span>
                <h3>Does the proposal fit the authority granted?</h3>
                <p>
                  Limits, permitted actions, delegation rights, and current
                  lineage define the hard boundary.
                </p>
              </article>
              <article>
                <span className="label">Preflight</span>
                <h3>
                  Would the projected Vault balance stay above its reserve?
                </h3>
                <p>
                  The current MVP checks the projected native Vault balance
                  against an inherited reserve boundary.
                </p>
              </article>
              <article>
                <span className="label">Escalation</span>
                <h3>Does crossing this boundary require owner review?</h3>
                <p>
                  The owner approves or denies the exact stored proposal, and
                  execution checks current state again.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section className="section-dark" id="authority-state">
          <div className="shell">
            <div className="section-head reveal">
              <h2>Authority stays bounded as things change.</h2>
              <p>
                Grantline evaluates current authority, preserves the active
                lineage, and checks an approved escalation again before
                execution.
              </p>
            </div>

            <div className="state-grid reveal">
              <article>
                <span className="label">Rules can tighten</span>
                <h3>
                  New Mandate rules are checked when the proposal is evaluated.
                </h3>
                <p>
                  A proposal signed under a wider boundary can stop when the
                  Mandate becomes more restrictive.
                </p>
              </article>
              <article>
                <span className="label">Authority can be revoked</span>
                <h3>Revocation preserves history and stops future use.</h3>
                <p>
                  Revocation preserves the lineage while preventing an inactive
                  Mandate or ancestor from authorising new execution.
                </p>
              </article>
              <article>
                <span className="label">Approval is not a bypass</span>
                <h3>Approval is checked again before execution.</h3>
                <p>
                  An approved escalation is checked again before capital moves,
                  so changed authority can still stop it.
                </p>
              </article>
              <article>
                <span className="label">
                  Delegation cannot expand authority
                </span>
                <h3>Delegation can narrow authority, never expand it.</h3>
                <p>
                  A sub-agent receives a narrower boundary, while restrictions
                  above it continue to apply.
                </p>
              </article>
            </div>

            <div className="delegation reveal">
              <div className="delegation-note">
                <span className="label">What that looks like in practice</span>
                <h3>Effective authority follows the active lineage.</h3>
                <p>
                  Effective authority is the current Mandate intersected with
                  active ancestor boundaries.
                </p>
              </div>

              <div
                className="lineage"
                aria-label="Illustrative delegated authority lineage"
              >
                <div className="lineage-card">
                  <strong>Owner</strong>
                  <small>source of authority</small>
                </div>
                <span className="lineage-line" aria-hidden="true">
                  <span>→</span>
                </span>
                <div className="lineage-card lineage-card-accent">
                  <strong>Primary agent</strong>
                  <small>bounded operating authority</small>
                </div>
                <span className="lineage-line" aria-hidden="true">
                  <span>→</span>
                </span>
                <div className="lineage-card">
                  <strong>Sub-agent</strong>
                  <small>narrower execution authority</small>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="vision">
          <div className="shell">
            <div className="section-head reveal">
              <div className="eyebrow">Where Grantline goes next</div>
              <h2>Extend the authority model without opening a bypass.</h2>
              <p>
                Future work adds policy, external context, integrations, and
                evidence around the same enforced execution boundary.
              </p>
            </div>

            <div className="future-grid reveal">
              <article>
                <span className="label">Authority policy</span>
                <h3>Validity and destination controls</h3>
                <p>
                  Pausing, validity windows, destination and capability
                  policies, and shared authority budgets.
                </p>
              </article>
              <article>
                <span className="label">External conditions</span>
                <h3>Guardians</h3>
                <p>
                  Planned conditions that can bring selected, attributable, and
                  time-bounded external context into authorisation.
                </p>
              </article>
              <article>
                <span className="label">Integration</span>
                <h3>SDK and API surfaces</h3>
                <p>
                  Client tools around the same underlying contract authority
                  model.
                </p>
              </article>
              <article>
                <span className="label">Decision evidence</span>
                <h3>Indexed decision evidence</h3>
                <p>
                  Indexing and assembled Decision Receipts that connect
                  proposals, authority, approval, and execution.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section className="cta">
          <div className="shell reveal">
            <div className="cta-brand">
              <GrantlineMark className="brand-mark" />
              <span>Grantline</span>
            </div>
            <h2>Let agents act. Keep authority bounded.</h2>
            <p>
              Give autonomous systems room to operate without turning their
              signing keys into unrestricted control over capital.
            </p>
            <div className="cta-actions">
              <button
                type="button"
                className="btn btn-primary coming-soon"
                disabled
              >
                Demo coming soon
              </button>
              <Link className="btn btn-quiet" href="/docs">
                Read the documentation
              </Link>
              <a
                className="btn btn-quiet"
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

      <footer className="footer">
        <div className="shell footer-row">
          <div className="footer-brand">
            <a className="brand" href="#top" aria-label="Grantline home">
              <GrantlineMark className="brand-mark" />
              <span>Grantline</span>
            </a>
            <p>The financial authorisation layer for AI agents.</p>
          </div>
          <div className="footer-links">
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
