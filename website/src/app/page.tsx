"use client";

import "./landing.css";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import Lenis from "lenis";
import GrantlineMark from "@/components/grantline-mark";
import { xUrl } from "@/lib/site";

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
      request: "Allocate $3,000 to approved tokenised Treasury asset",
      rows: [
        ["Transaction limit", "PASS", "ok"],
        ["Approved asset", "PASS", "ok"],
        ["Minimum liquidity", "PASS", "ok"],
      ],
      decision: "ALLOW",
      tone: "allow",
      reason: "Authority and required conditions are satisfied.",
      meta: '<a href="#">Executed \u00B7 X Layer Testnet \u2197</a>',
    },
    escalate: {
      request: "Allocate $8,500 to approved tokenised Treasury asset",
      rows: [
        ["Transaction limit", "PASS", "ok"],
        ["Approved asset", "PASS", "ok"],
        ["Human approval", "REQUIRED", "warn"],
      ],
      decision: "ESCALATE",
      tone: "escalate",
      reason: "Human approval is required above the $7,500 threshold.",
      meta: "",
    },
    deny: {
      request: "Borrow $20,000 against Treasury Vault",
      rows: [
        ["Transaction limit", "OUTSIDE", "bad"],
        ["Borrowing", "NOT PERMITTED", "bad"],
        ["Mandate authority", "FAIL", "bad"],
      ],
      decision: "DENY",
      tone: "deny",
      reason: "Borrowing is outside the delegated Mandate.",
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
            <Link href="/docs">Docs</Link>
            <a className="btn" href="#">
              Try Grantline
            </a>
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
              Docs
            </Link>
            <a className="mobile-demo" href="#" onClick={closeMenu}>
              Try Grantline
            </a>
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
                Grantline lets people and organisations define exactly what an
                agent can do, under what conditions, and when another authority
                needs to step in.
              </p>
              <div className="hero-principle">
                Your AI agent proposes. Grantline authorises.
              </div>
              <div className="hero-actions">
                <a className="btn primary" href="#mechanism">
                  See how Grantline works
                </a>
                <a className="btn" href="#">
                  Try Grantline
                </a>
              </div>
            </div>

            <div
              className="auth-console reveal"
              aria-label="Example Grantline authorisation event"
            >
              <div className="console-top">
                <span className="console-title">Authorisation event</span>
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
                    <div
                      className="decision-meta"
                      dangerouslySetInnerHTML={{ __html: current.meta }}
                    />
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
                a precise answer to what an agent can do with that access.
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
                whether it has authority to do it, runs the conditions selected
                by the owner, and returns a decision before capital moves.
              </p>
            </div>
            <div className="flow-track reveal">
              <div className="flow-step">
                <div className="flow-node">Agent</div>
                <h3>Proposes</h3>
                <p>Chooses an action.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Mandate</div>
                <h3>Authorises</h3>
                <p>Checks delegated authority.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Conditions</div>
                <h3>Verify</h3>
                <p>Runs required checks.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Decision</div>
                <h3>Resolves</h3>
                <p>Allow, Escalate, Deny.</p>
              </div>
              <div className="flow-step">
                <div className="flow-node">X Layer</div>
                <h3>Executes</h3>
                <p>Moves capital only when authorised.</p>
              </div>
              <div className="flow-step control">
                <div className="flow-node">Record</div>
                <h3>Traces</h3>
                <p>Links the authorisation decision to its onchain outcome.</p>
              </div>
            </div>
            <div
              className="condition-branch reveal"
              aria-label="Optional authorisation conditions"
            >
              <div className="condition-item">
                <strong>Guardian</strong>
                <p>Checks relevant external conditions.</p>
              </div>
              <div className="sep"></div>
              <div className="condition-item">
                <strong>Preflight</strong>
                <p>Tests the resulting financial state.</p>
              </div>
              <div className="sep"></div>
              <div className="condition-item">
                <strong>Escalation</strong>
                <p>Defers execution requiring human approval.</p>
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
                <h3>Define exactly what an agent can do.</h3>
                <p>
                  Set limits, actions, approvals, and delegation rights, then
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
                  Keep delegated capital separate from unrestricted funds so an
                  agent operates only against what has been made available to
                  it.
                </p>
                <div className="model-tags">
                  <span className="tag">Capital scope</span>
                  <span className="tag">Isolation</span>
                </div>
              </article>
              <article className="model-cell">
                <div className="model-num">03 / CONDITIONS</div>
                <div className="model-topic">Guardians + Preflight</div>
                <h3>
                  Make authority conditional on the state around the action.
                </h3>
                <p>
                  Require external condition checks and test whether the
                  proposed resulting state stays inside configured boundaries.
                </p>
                <div className="model-tags">
                  <span className="tag">External checks</span>
                  <span className="tag">Stress limits</span>
                  <span className="tag">Liquidity floor</span>
                </div>
              </article>
              <article className="model-cell">
                <div className="model-num">04 / ACCOUNTABILITY</div>
                <div className="model-topic">Records</div>
                <h3>Trace every proposal, decision, and execution.</h3>
                <p>
                  Show what was proposed, which authority applied, what checks
                  ran, which decision was returned, and what was executed.
                </p>
                <div className="model-tags">
                  <span className="tag">Decision receipt</span>
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
              <div className="section-kicker">Delegated authority</div>
              <h2>
                Delegation passes authority down, but never beyond its source.
              </h2>
              <p>
                Each handoff inherits an upper bound from the authority above
                it. An agent can delegate less capital, fewer actions, fewer
                assets, shorter duration, or stricter approvals. It cannot
                create authority it was never granted.
              </p>
              <div className="delegation-principle">
                Every delegation stays inside its parent Mandate and remains
                traceable to the original authority.
              </div>
            </div>
            <div className="tree reveal" aria-label="Delegation graph example">
              <div className="tree-card">
                <strong>Company</strong>
                <small>$500,000 treasury authority</small>
              </div>
              <div className="authority-line" aria-hidden="true" />
              <div className="tree-card">
                <strong>Treasury Agent</strong>
                <small>$50,000 execution authority &middot; no borrowing</small>
              </div>
              <div className="authority-line" aria-hidden="true" />
              <div className="tree-card">
                <strong>Execution Agent</strong>
                <small>
                  $5,000 payments &middot; approved assets &middot; no further
                  delegation
                </small>
              </div>
              <div className="denied-branch">
                <div className="branch-item good">
                  $3,000 PAYMENT
                  <br />
                  <span className="ok">WITHIN AUTHORITY</span>
                </div>
                <div className="branch-item bad">
                  $100,000 BORROW
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
                A Mandate can require external condition checks, resulting state
                checks, and human approval thresholds before an action is
                authorised.
              </p>
            </div>

            <div
              className="proof-artifact reveal"
              aria-label="Grantline authorisation proof example"
            >
              <div className="proof-head">
                <span className="proof-head-title">Authorisation trace</span>
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
                    Allocate $3,000 to approved tokenised Treasury asset
                  </div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Mandate</div>
                  <div className="proof-value mono ok">PASS</div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Guardian</div>
                  <div className="proof-value mono ok">PASS</div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Preflight</div>
                  <div className="proof-value mono ok">PASS</div>
                </div>
                <div className="proof-row">
                  <div className="proof-label">Human approval</div>
                  <div className="proof-value mono muted">NOT REQUIRED</div>
                </div>
                <div className="proof-row emphasis">
                  <div className="proof-label">Decision</div>
                  <div className="proof-value mono ok">ALLOW</div>
                </div>
                <div className="proof-row evidence">
                  <div className="proof-label">Execution</div>
                  <div className="proof-value mono">
                    <a className="proof-link" href="#">
                      X LAYER TESTNET &middot; CONFIRMED &#8599;
                    </a>
                  </div>
                </div>
                <div className="proof-row evidence">
                  <div className="proof-label">Receipt</div>
                  <div className="proof-value mono">
                    <a className="proof-link" href="#">
                      VIEW DECISION RECEIPT &#8599;
                    </a>
                  </div>
                </div>
              </div>
            </div>

            <div className="proof-cta reveal" aria-label="Proof and next steps">
              <a className="btn" href="#">
                View contract &#8599;
              </a>
              <Link className="btn" href="/docs">
                Read how enforcement works &#8599;
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
                <div className="future-phase">Now / MVP</div>
                <div className="future-card">
                  <h3>Bounded agent authority</h3>
                  <p>
                    Prove that an agent can operate autonomously with capital
                    without receiving unrestricted control over it.
                  </p>
                  <div className="model-tags">
                    <span className="tag">Vaults</span>
                    <span className="tag">Mandates</span>
                    <span className="tag">Delegation</span>
                    <span className="tag">Guardian</span>
                    <span className="tag">Preflight</span>
                    <span className="tag">Revocation</span>
                    <span className="tag">Records</span>
                  </div>
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
                    Treasury, payments, procurement, execution, and risk agents
                    operating through connected but bounded authority graphs.
                  </p>
                </div>
              </div>
              <div className="future-item">
                <div className="future-phase">Ecosystem</div>
                <div className="future-card">
                  <h3>Authorisation infrastructure</h3>
                  <p>
                    Guardian ecosystems, reusable policy templates,
                    organisation-specific preflight, and agent-to-agent
                    delegation.
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
              Grantline governs the authority between autonomous intent and
              financial execution.
            </p>
            <div className="cta-actions">
              <a className="btn primary" href="#">
                See Grantline in action
              </a>
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
              <Link href="/docs">Docs</Link>
              <a href="#">Try Grantline</a>
              <a href={xUrl} target="_blank" rel="noreferrer">
                X / @usegrantline &#8599;
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
