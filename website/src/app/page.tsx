"use client";

import "./landing.css";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import Lenis from "lenis";
import GrantlineMark from "@/components/grantline-mark";
import { repositoryUrl, xUrl } from "@/lib/site-links";

export default function Home() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [activeCase, setActiveCase] = useState("allow");

  const closeMenu = useCallback(() => setMenuOpen(false), []);

  useEffect(() => {
    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const navWrap = document.querySelector(".nav-wrap");
    let lenis: Lenis | null = null;
    let rafId = 0;

    if (!reduceMotion) {
      lenis = new Lenis({
        duration: 1.05,
        smoothWheel: true,
        wheelMultiplier: 0.9,
        touchMultiplier: 1,
      });
      function raf(time: number) {
        lenis!.raf(time);
        rafId = requestAnimationFrame(raf);
      }
      rafId = requestAnimationFrame(raf);
    }

    function scrollToAnchor(target: string) {
      const el = document.querySelector(target);
      if (!el) return;
      closeMenu();

      const performScroll = () => {
        const navHeight = navWrap
          ? ((navWrap.querySelector("nav") as HTMLElement)?.offsetHeight ?? 0)
          : 0;
        if (lenis) {
          lenis.scrollTo(el as HTMLElement, { offset: -navHeight });
        } else {
          const top =
            el.getBoundingClientRect().top + window.scrollY - navHeight;
          window.scrollTo({
            top,
            behavior: reduceMotion ? "auto" : "smooth",
          });
        }
      };

      requestAnimationFrame(() => requestAnimationFrame(performScroll));
    }

    const anchorLinks = document.querySelectorAll('a[href^="#"]');
    const anchorHandlers: Array<[Element, (e: Event) => void]> = [];
    anchorLinks.forEach((link) => {
      const handler = (e: Event) => {
        e.preventDefault();
        const target = link.getAttribute("href");
        if (!target || target === "#") return;
        if (!document.querySelector(target)) return;
        scrollToAnchor(target);
      };
      link.addEventListener("click", handler);
      anchorHandlers.push([link, handler]);
    });

    const onKeydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeMenu();
    };
    const onResize = () => {
      if (window.innerWidth > 720) closeMenu();
    };
    window.addEventListener("keydown", onKeydown);
    window.addEventListener("resize", onResize);

    const revealEls = document.querySelectorAll(".reveal");
    if ("IntersectionObserver" in window && !reduceMotion) {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              entry.target.classList.add("visible");
              io.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.12 },
      );
      revealEls.forEach((el) => io.observe(el as HTMLElement));
    } else {
      revealEls.forEach((el) => el.classList.add("visible"));
    }

    return () => {
      lenis?.destroy();
      cancelAnimationFrame(rafId);
      anchorHandlers.forEach(([el, handler]) => {
        el.removeEventListener("click", handler);
      });
      window.removeEventListener("keydown", onKeydown);
      window.removeEventListener("resize", onResize);
    };
  }, [closeMenu]);

  const authorizationCases: Record<
    string,
    {
      request: string;
      rows: [string, string, string][];
      decision: string;
      tone: string;
      reason: string;
      meta: string;
    }
  > = {
    allow: {
      request: "Allocate $25,000 within an active Mandate",
      rows: [
        ["Mandate boundary", "PASS", "ok"],
        ["Required conditions", "PASS", "ok"],
        ["Owner approval", "NOT REQUIRED", "muted"],
      ],
      decision: "ALLOW",
      tone: "allow",
      reason: "The action is within the authority granted to the agent.",
      meta: "Illustrative product scenario",
    },
    escalate: {
      request: "Allocate $100,000 above the agent's approval threshold",
      rows: [
        ["Mandate boundary", "REVIEW", "warn"],
        ["Required conditions", "PASS", "ok"],
        ["Owner approval", "REQUIRED", "warn"],
      ],
      decision: "ESCALATE",
      tone: "escalate",
      reason:
        "The Mandate allows the request to continue only after owner approval.",
      meta: "Illustrative product scenario",
    },
    deny: {
      request: "Move $250,000 outside the active Mandate",
      rows: [
        ["Mandate boundary", "FAIL", "bad"],
        ["Authority", "EXCEEDED", "bad"],
        ["Execution", "NOT SUBMITTED", "bad"],
      ],
      decision: "DENY",
      tone: "deny",
      reason:
        "The requested action is outside the authority granted to the agent.",
      meta: "No execution submitted.",
    },
  };

  const current = authorizationCases[activeCase];

  const handleTabKey = (e: React.KeyboardEvent, idx: number) => {
    if (!["ArrowLeft", "ArrowRight"].includes(e.key)) return;
    e.preventDefault();
    const keys = Object.keys(authorizationCases);
    const delta = e.key === "ArrowRight" ? 1 : -1;
    const next = keys[(idx + delta + keys.length) % keys.length];
    setActiveCase(next);
    (
      (e.currentTarget as HTMLElement).parentElement?.querySelector(
        `[data-case="${next}"]`,
      ) as HTMLElement
    )?.focus();
  };

  return (
    <div className="landing">
      <div className="page-grid" />

      <div className="nav-wrap">
        <nav className="shell" aria-label="Primary navigation">
          <a className="brand-lockup" href="#top" aria-label="Grantline home">
            <GrantlineMark className="brand-mark" />
            <span>Grantline</span>
          </a>
          <div className="nav-links">
            <a href="#mechanism">How it works</a>
            <a href="#platform">Platform</a>
            <a href="#vision">Vision</a>
            <Link href="/docs">Documentation</Link>
            <span className="btn coming-soon" aria-disabled="true">
              Demo coming soon
            </span>
          </div>
          <button
            className="menu-toggle"
            type="button"
            aria-label={menuOpen ? "Close navigation" : "Open navigation"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen(!menuOpen)}
          >
            <span className="menu-icon" aria-hidden="true">
              <span></span>
              <span></span>
              <span></span>
            </span>
          </button>
        </nav>
        <div className="mobile-menu" data-open={menuOpen}>
          <div className="mobile-menu-inner">
            <a href="#mechanism" onClick={closeMenu}>
              How it works
            </a>
            <a href="#platform" onClick={closeMenu}>
              Platform
            </a>
            <a href="#vision" onClick={closeMenu}>
              Vision
            </a>
            <Link href="/docs" onClick={closeMenu}>
              Documentation
            </Link>
            <span className="mobile-demo" aria-disabled="true">
              Demo coming soon
            </span>
          </div>
        </div>
      </div>

      <main id="top">
        <header className="hero">
          <div className="shell hero-grid">
            <div className="reveal">
              <div className="eyebrow">
                Programmable financial authority for AI agents
              </div>
              <h1>
                Give AI agents capital without giving them unlimited authority.
              </h1>
              <p className="hero-copy">
                Grantline lets people and organisations define what an agent is
                allowed to do, under what conditions, and when another authority
                needs to step in. The result is autonomy with a defined
                boundary, owner control, and an auditable path from intent to
                execution.
              </p>
              <div className="hero-principle">
                Your AI agent proposes. Grantline authorises.
              </div>
              <div className="hero-actions">
                <a className="btn primary" href="#mechanism">
                  See how Grantline works
                </a>
                <span className="btn coming-soon" aria-disabled="true">
                  Demo coming soon
                </span>
              </div>
            </div>

            <div
              className="auth-console reveal"
              aria-label="Illustrative Grantline authorisation scenarios"
            >
              <div className="console-top">
                <span className="console-title">
                  Illustrative authorisation scenarios
                </span>
                <span className="console-status">MANDATE ACTIVE</span>
              </div>
              <div className="decision-explore-label">
                <strong>Explore outcomes</strong> &middot; select a decision
                state
              </div>
              <div
                className="decision-tabs"
                role="tablist"
                aria-label="Authorisation examples"
              >
                {(Object.keys(authorizationCases) as string[]).map(
                  (key, idx) => (
                    <button
                      key={key}
                      className="decision-tab"
                      role="tab"
                      aria-selected={activeCase === key}
                      data-case={key}
                      onClick={() => setActiveCase(key)}
                      onKeyDown={(e) => handleTabKey(e, idx)}
                    >
                      {key === "allow"
                        ? "Allowed"
                        : key === "escalate"
                          ? "Escalated"
                          : "Denied"}
                    </button>
                  ),
                )}
              </div>
              <div className="console-body">
                <div className="request-block">
                  <div className="label">Proposed action</div>
                  <div className="request-name">{current.request}</div>
                  <div className="request-agent">AI Treasury Agent</div>
                </div>
                <div className="authority-line" aria-hidden="true" />
                <div className="mandate-card">
                  <div className="mandate-head">
                    <span>Mandate</span>
                    <span>TREASURY_EXECUTION_V3</span>
                  </div>
                  <div className="mandate-rows">
                    {current.rows.map(([label, value, tone]) => (
                      <div className="mandate-row" key={label}>
                        <span>{label}</span>
                        <span className={tone}>{value}</span>
                      </div>
                    ))}
                  </div>
                </div>
                <div className={`decision-output ${current.tone}`}>
                  <div>
                    <div className="label">Decision</div>
                    <div className="decision-word">{current.decision}</div>
                    <div className="decision-meta">{current.meta}</div>
                  </div>
                  <div className="decision-reason">{current.reason}</div>
                </div>
              </div>
            </div>
          </div>
        </header>

        <section>
          <div className="shell">
            <div className="section-head reveal">
              <div className="section-kicker">The question changes</div>
              <h2>A wallet proves access. Grantline defines authority.</h2>
              <p className="section-copy">
                Autonomous systems need more than permission to sign. They need
                a precise answer to what an agent is allowed to do with that
                access. Signing proves that an agent made the proposal;
                Grantline determines whether that proposal can use the capital
                and under what conditions.
              </p>
            </div>
            <div className="question-frame reveal">
              <div className="question-shift">
                <article className="question-side">
                  <div className="question-title">Wallet layer</div>
                  <div>
                    <div className="question-main">
                      Who can access and sign for these assets?
                    </div>
                    <p className="question-note">
                      Identity, custody and signing determine who can act.
                    </p>
                  </div>
                </article>
                <article className="question-side grantline">
                  <div className="question-title">Authority layer</div>
                  <div>
                    <div className="question-main">
                      What is this agent actually allowed to do?
                    </div>
                    <p className="question-note">
                      Grantline turns access into bounded, conditional and
                      revocable authority.
                    </p>
                  </div>
                </article>
              </div>
              <div
                className="authority-questions"
                aria-label="Questions Grantline answers"
              >
                <div className="authority-question">
                  <span></span>How much authority does it have?
                </div>
                <div className="authority-question">
                  <span></span>Where did that authority come from?
                </div>
                <div className="authority-question">
                  <span></span>What conditions must be satisfied?
                </div>
                <div className="authority-question">
                  <span></span>When should another authority step in?
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="mechanism">
          <div className="shell">
            <div className="section-head reveal">
              <div className="section-kicker">Authorisation flow</div>
              <h2>Authority sits between intent and execution.</h2>
              <p className="section-copy">
                An agent chooses what it wants to do. Grantline evaluates
                whether it has authority to do it, checks the configured safety
                conditions, and returns <code>ALLOW</code>,{" "}
                <code>ESCALATE</code>, or <code>DENY</code> before capital
                moves.
              </p>
            </div>
            <div className="flow-track reveal">
              <div className="flow-step">
                <div className="flow-node">Agent</div>
                <h3>Proposes</h3>
                <p>Turns intent into an action.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Mandate</div>
                <h3>Authorises</h3>
                <p>Defines what the agent is allowed to do.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Conditions</div>
                <h3>Checks</h3>
                <p>Runs the configured safety checks.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Decision</div>
                <h3>Resolves</h3>
                <p>Allow, Escalate, Deny.</p>
              </div>
              <div className="flow-step">
                <div className="flow-node">X Layer</div>
                <h3>Executes</h3>
                <p>Moves capital only after authorisation.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Record</div>
                <h3>Traces</h3>
                <p>Records successful outcomes onchain.</p>
              </div>
            </div>
            <div
              className="condition-branch reveal"
              aria-label="Optional authorisation conditions"
            >
              <div className="condition-item">
                <strong>Guardians</strong>
                <p>
                  Checks outside context, like asset eligibility, markets, or
                  counterparties.
                </p>
              </div>
              <div className="sep"></div>
              <div className="condition-item">
                <strong>Preflight</strong>
                <p>Checks that the Vault stays inside its safety boundary.</p>
              </div>
              <div className="sep"></div>
              <div className="condition-item">
                <strong>Escalation</strong>
                <p>
                  Brings an owner into the decision when more authority is
                  needed.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section id="platform">
          <div className="shell">
            <div className="section-head reveal">
              <div className="section-kicker">GRANTLINE PLATFORM</div>
              <h2>Financial authority has four parts.</h2>
              <p className="section-copy">
                The system stays understandable by grouping the product around
                what authority is, what capital it applies to, which conditions
                matter, and what remains afterwards.
              </p>
            </div>
            <div className="model-grid reveal">
              <article className="model-cell">
                <div className="model-num">01 / AUTHORITY</div>
                <div className="model-topic">Mandates + Delegation</div>
                <h3>Define exactly what an agent may do.</h3>
                <p>
                  Define limits, actions, approvals, and delegation rights, then
                  preserve the source of that authority as it moves between
                  agents.
                </p>
                <div className="model-tags">
                  <span className="tag">Limits</span>
                  <span className="tag">Actions</span>
                  <span className="tag">Approvals</span>
                  <span className="tag">Delegation</span>
                </div>
              </article>
              <article className="model-cell">
                <div className="model-num">02 / CAPITAL</div>
                <div className="model-topic">Vaults</div>
                <h3>Limit the capital that authority applies to.</h3>
                <p>
                  Keep capital behind a controlled Vault, so agents receive
                  authority to act without receiving unrestricted ownership of
                  the funds.
                </p>
                <div className="model-tags">
                  <span className="tag">Capital scope</span>
                  <span className="tag">Isolation</span>
                </div>
              </article>
              <article className="model-cell">
                <div className="model-num">03 / CONDITIONS</div>
                <div className="model-topic">Checks + Approval</div>
                <h3>
                  Make authority conditional on what surrounds the action.
                </h3>
                <p>
                  Preflight checks the Vault’s safety boundary after an action.
                  Guardians will add context such as asset eligibility, markets,
                  counterparties, or organisation policies.
                </p>
                <div className="model-tags">
                  <span className="tag">Preflight</span>
                  <span className="tag">Owner approval</span>
                  <span className="tag">Guardians planned</span>
                </div>
              </article>
              <article className="model-cell">
                <div className="model-num">04 / ACCOUNTABILITY</div>
                <div className="model-topic">Records</div>
                <h3>Connect authority to outcome.</h3>
                <p>
                  Successful Mandate, approval, custody, and execution changes
                  leave an onchain record, connecting the authority behind an
                  action to its outcome.
                </p>
                <div className="model-tags">
                  <span className="tag">Onchain records</span>
                  <span className="tag">Traceability</span>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section
          className="thesis-break"
          aria-label="Grantline authority principle"
        >
          <div className="shell reveal">
            <p className="thesis-statement">
              An agent can act freely within{" "}
              <span className="accent">its Mandate.</span>
              <br />
              Beyond it, <span className="accent">authority ends.</span>
            </p>
          </div>
        </section>

        <section>
          <div className="shell delegation-wrap">
            <div className="delegation-copy reveal">
              <div className="section-kicker">Illustrative delegation</div>
              <h2>
                Delegation passes authority down, but never beyond its source.
              </h2>
              <p>
                Every delegation passes down a narrower version of the authority
                above it: a smaller budget, fewer permitted actions, tighter
                conditions, or less ability to delegate. Every sub-agent remains
                tied to the authority above it and to the original source of
                control.
              </p>
              <div className="delegation-principle">
                Every delegation stays inside its parent Mandate and remains
                traceable to the original authority.
              </div>
            </div>
            <div
              className="tree reveal"
              aria-label="Illustrative delegation hierarchy"
            >
              <div className="tree-card">
                <strong>Company</strong>
                <small>$5M treasury authority</small>
              </div>
              <div className="authority-line" aria-hidden="true" />
              <div className="tree-card">
                <strong>Treasury Agent</strong>
                <small>$500k operating authority</small>
              </div>
              <div className="authority-line" aria-hidden="true" />
              <div className="tree-card">
                <strong>Execution Agent</strong>
                <small>
                  $50k action authority &middot; no further delegation
                </small>
              </div>
              <div className="denied-branch">
                <div className="branch-item good">
                  $25k ACTION
                  <br />
                  <span className="ok">WITHIN AUTHORITY</span>
                </div>
                <div className="branch-item bad">
                  $250k ACTION
                  <br />
                  <span className="bad">AUTHORITY STOPS</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="scenario">
          <div className="shell">
            <div className="section-head reveal">
              <div className="section-kicker">Conditional authority</div>
              <h2>One proposal can require more than a spending limit.</h2>
              <p className="section-copy">
                A Mandate can combine authority limits with resulting-state
                checks and owner approval, so an action is evaluated against
                both what the agent is allowed to do and what the action would
                leave behind.
              </p>
            </div>

            <div
              className="proof-artifact reveal"
              aria-label="Illustrative Grantline authorisation trace"
            >
              <div className="proof-head">
                <span className="proof-head-title">
                  Illustrative authorisation trace
                </span>
                <span className="proof-head-status">MANDATE ACTIVE</span>
              </div>
              <div className="proof-body">
                <div className="proof-row">
                  <div className="proof-label">Proposed by</div>
                  <div className="proof-value">AI Treasury Agent</div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Action</div>
                  <div className="proof-value">
                    Signed action plan for a $25,000 allocation
                  </div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Mandate</div>
                  <div className="proof-value mono ok">PASS</div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Preflight</div>
                  <div className="proof-value mono ok">PASS</div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Owner approval</div>
                  <div className="proof-value mono muted">NOT REQUIRED</div>
                </div>
                <div className="proof-row emphasis">
                  <div className="proof-label">Decision</div>
                  <div className="proof-value mono ok">ALLOW</div>
                </div>
                <div className="proof-row evidence">
                  <div className="proof-label">Execution</div>
                  <div className="proof-value mono muted">
                    X LAYER TESTNET &middot; CONFIRMED
                  </div>
                </div>
                <div className="proof-row evidence">
                  <div className="proof-label">Record</div>
                  <div className="proof-value mono muted">
                    EXECUTION RECORDED
                  </div>
                </div>
              </div>
            </div>

            <p className="proof-note reveal">
              Guardians will extend this decision with context from outside the
              action itself, helping determine whether an otherwise permitted
              action should still proceed. Guardian checks are planned for a
              future release.
            </p>

            <div className="proof-cta reveal" aria-label="Proof and next steps">
              <a
                className="btn"
                href={`${repositoryUrl}/tree/main/contracts`}
                target="_blank"
                rel="noreferrer nofollow"
              >
                View the implementation
              </a>
              <Link className="btn" href="/docs">
                Read how enforcement works
              </Link>
            </div>
          </div>
        </section>

        <section id="vision">
          <div className="shell">
            <div className="section-head reveal">
              <div className="section-kicker">Vision</div>
              <h2>Start with one agent. Scale to autonomous organisations.</h2>
              <p className="section-copy">
                The same authority model can expand from bounded agent spending
                into richer policies, specialised agent hierarchies, external
                control modules, and eventually behavioural history that other
                financial systems can evaluate.
              </p>
            </div>
            <div className="future-track reveal">
              <div className="future-item">
                <div className="future-phase">Now / Proven MVP</div>
                <div className="future-card">
                  <h3>Bounded agent authority</h3>
                  <p>
                    Prove that agents can operate autonomously with capital,
                    then delegate narrower authority to sub-agents without
                    giving them unrestricted control over it.
                  </p>
                  <div className="model-tags">
                    <span className="tag">Vaults</span>
                    <span className="tag">Mandates</span>
                    <span className="tag">Delegation</span>
                    <span className="tag">Preflight</span>
                    <span className="tag">Revocation</span>
                    <span className="tag">Records</span>
                  </div>
                </div>
              </div>
              <div className="future-item">
                <div className="future-phase">Planned</div>
                <div className="future-card">
                  <h3>Guardian conditions</h3>
                  <p>
                    Guardians bring outside context into an authorisation
                    decision, such as asset eligibility, market conditions,
                    counterparty status, or organisation policy, so an action is
                    judged on more than the Mandate alone.
                  </p>
                </div>
              </div>
              <div className="future-item">
                <div className="future-phase">Expand</div>
                <div className="future-card">
                  <h3>Richer authority</h3>
                  <p>
                    Temporary permissions, multi-party approvals, reusable
                    Mandates, expiry, emergency permissions, and conditional
                    changes in authority.
                  </p>
                </div>
              </div>
              <div className="future-item">
                <div className="future-phase">Scale</div>
                <div className="future-card">
                  <h3>Agent organisations</h3>
                  <p>
                    Extend today’s bounded delegation into connected treasury,
                    payments, procurement, execution, and risk agents, each
                    operating within its own authority boundary.
                  </p>
                </div>
              </div>
              <div className="future-item">
                <div className="future-phase">Ecosystem</div>
                <div className="future-card">
                  <h3>Authorisation infrastructure</h3>
                  <p>
                    Guardian ecosystems, reusable policy templates, and
                    organisation-specific preflight.
                  </p>
                </div>
              </div>
              <div className="future-item">
                <div className="future-phase">Long term</div>
                <div className="future-card">
                  <h3>Economic accountability</h3>
                  <p>
                    Records can become trusted behavioural history for external
                    reputation, credit, insurance, compliance, and risk systems.
                  </p>
                  <div className="model-tags">
                    <span className="tag">Reputation</span>
                    <span className="tag">Credit</span>
                    <span className="tag">Insurance</span>
                    <span className="tag">Compliance</span>
                    <span className="tag">Risk</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section className="cta">
          <div className="shell reveal">
            <div className="cta-brand">
              <GrantlineMark className="brand-mark" />
              <span>Grantline</span>
            </div>
            <h2>Give agents autonomy. Keep authority bounded.</h2>
            <p>
              Define the authority before the action, then let agents act within
              clear boundaries and owner control.
            </p>
            <div className="cta-actions">
              <span className="btn primary coming-soon" aria-disabled="true">
                Demo coming soon
              </span>
              <Link className="btn" href="/docs">
                Read the documentation
              </Link>
            </div>
          </div>
        </section>
      </main>

      <footer>
        <div className="shell footer-row">
          <div className="footer-top">
            <a
              className="footer-lockup"
              href="#top"
              aria-label="Grantline home"
            >
              <GrantlineMark className="brand-mark" />
              <span>Grantline</span>
            </a>
          </div>
          <div className="footer-bottom">
            <div className="footer-note">
              Programmable financial authority for AI agents.
            </div>
            <div className="footer-links">
              <a href="#mechanism">How it works</a>
              <a href="#platform">Platform</a>
              <a href="#vision">Vision</a>
              <Link href="/docs">Documentation</Link>
              <span className="footer-demo">Demo coming soon</span>
              <a href={xUrl} target="_blank" rel="noreferrer nofollow">
                X / @usegrantline &#8599;
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
