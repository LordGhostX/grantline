# Grantline Working Memory

## Purpose

Grantline is programmable financial authority for AI agents. The agent proposes an action, while Grantline determines whether that action is authorised under an active Mandate and its surrounding conditions.

This file is the project-wide working memory for future agents and contributors. Keep implementation details in the nearest package-level `AGENTS.md` and keep this file focused on shared context, boundaries, decisions, and handoffs.

## Current repository map

```text
.
├── AGENTS.md                 # Project-wide working memory
├── BRIEF.md                  # Product brief
├── plans/                    # Local, ignored planning documents
├── website/                  # Next.js landing page and Fumadocs documentation
│   └── AGENTS.md              # Website-local working memory
└── contracts/                # Foundry workspace and future Grantline contracts
    ├── AGENTS.md
    ├── foundry.toml
    ├── src/
    ├── test/
    ├── script/
    └── lib/
```

Future application boundaries are expected to be `sdk/` for agent-facing client libraries and `api/` for backend orchestration and records. The `website/` boundary now owns the Next.js landing, demo, and documentation surfaces; see `website/AGENTS.md` for package-local guidance. Create a local `AGENTS.md` when each additional package is introduced instead of putting package-specific details here.

## Product invariants

- The agent decides what it wants to do; Grantline decides whether it is allowed to do it.
- Vault capital must be unreachable through an agent-controlled bypass path.
- `ALLOW`, `ESCALATE`, and `DENY` are authorisation outcomes, not execution outcomes.
- An authorised action can still fail during downstream execution, and that must remain distinguishable from `DENY`.
- Delegated authority may become narrower, never broader, than its parent authority.
- Revocation preserves historical lineage while preventing future authority use.
- Public-facing product copy uses UK English, including `authorisation`, `authorised`, and `tokenised`.

## Current status

The repository contains the product brief, the Next.js/Fumadocs website foundation, and the working contracts loop. The website has the landing page, Phase 1 concept docs, Phase 2 enforcement and execution docs, Phase 3 integrator guides and contract reference pages, Fumadocs search and LLM routes, metadata, favicon, robots, sitemap, ESLint, Vercel Web Analytics, and reproducible Bun setup; its package-local handoff is in `website/AGENTS.md`. Its canonical site URL is resolved on the server from `NEXT_PUBLIC_SITE_URL` with a `VERCEL_URL` fallback, while browser-safe repository and X links live separately so deployment-only environment variables cannot break hydration. The contracts workspace now has the Vault, nested mandate rules, typed ActionPlan and signatures, `ALLOW`/`ESCALATE`/`DENY` evaluation, full-plan escalation storage, owner approval or denial, shared nonce replay protection and escalation reservations, executor re-evaluation, native-balance Preflight checks, onchain execution records, deployment verification with runtime-hash validation, and parent/child delegation with inherited authority and lineage revocation. `VaultExecutor` also has one storage-backed reentrancy lock across normal and escalated entrypoints, so a recipient cannot start a nested plan against a stale balance snapshot. All local tests pass. A fresh X Layer Phase 3 stack is deployed, recorded in the tracked manifest, verified, and exercised end to end; the live evidence is in `contracts/AGENTS.md`. Sponsored transaction submission, offchain indexing, guardian conditions, production USD value resolution, behavioural history, and receipt assembly remain deferred.

Sponsored submission remains deferred because the integration evidence uses the agent as the actual transaction submitter; users currently submit the transaction and pay its gas directly.

## Decision log

| Date       | Decision                                                                                  | Reason and impact                                                                                                                                                                                                                                                      |
| ---------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Keep blockchain files under `contracts/`.                                                 | The repository will also contain a website, SDKs, and API, so root-level tooling would make ownership and commands ambiguous.                                                                                                                                          |
| 2026-08-11 | Use `AGENTS.md` as the working-memory convention.                                         | Agents discover the file automatically, and nested files can document package-local boundaries without bloating the root context.                                                                                                                                      |
| 2026-08-11 | Keep deployment identity in a tracked contracts manifest.                                 | Deployment scripts need one reviewable source for addresses, dependency wiring, runtime hashes, and current Vault authority.                                                                                                                                           |
| 2026-08-12 | Store mandate policy in nested rules and make limit overruns optionally escalatable.      | Native and USD limits stay adjacent to their flags, while the evaluator can route configured overruns through explicit owner approval without weakening hard-deny rules.                                                                                               |
| 2026-08-12 | Store complete escalated plans in a dedicated manager.                                    | Approval and later execution remain decoupled from the original submitting process, while the executor re-evaluates current mandate state before moving capital.                                                                                                       |
| 2026-08-12 | Use aggregate native/USD amount ranges for mandate transaction bounds.                    | Minimums and maximums are denomination-aware, each bound can be disabled with zero, and transaction minimums remain separate from future Vault liquidity rules.                                                                                                        |
| 2026-08-12 | Keep Mandate updates live and allow denial after revocation.                              | Current rules are checked at execution, revocation blocks approval and execution, while the Vault owner can still close pending revoked escalations with a denial.                                                                                                     |
| 2026-08-12 | Store escalation nonce reservations in MandateRegistry.                                   | Shared reservation state survives manager and executor replacement, so pending or denied plans cannot become executable through the normal path after authority rotation.                                                                                              |
| 2026-08-12 | Deploy and verify a fresh Phase 3 X Layer stack before live integration.                  | The non-upgradeable Vault, registry, evaluator, escalation manager, and executor must share one manifest-defined wiring; the live flow covers delegation, inherited Preflight, escalation, revocation, and replay protection.                                          |
| 2026-08-12 | Use separate primary and delegated testnet agents in integration evidence.                | The root agent creates a child for the delegated agent, which creates a depth-two grandchild; separate funded EOAs prove authority inheritance and signing boundaries without recording private keys.                                                                  |
| 2026-08-12 | Force `canDelegate` off on depth-two Mandate updates.                                     | The delegation cap must remain true after policy updates, so a grandchild cannot report delegation enabled even though no further child can be created.                                                                                                                |
| 2026-08-12 | Add native-balance Preflight as a separate inherited rule set.                            | The evaluator checks projected Vault balance after aggregate native outflow, including token-only plans, and routes a configured reserve breach to `DENY` or `ESCALATE`.                                                                                               |
| 2026-08-12 | Guard both executor entrypoints with OpenZeppelin `ReentrancyGuard`.                      | Normal and escalated plans share one lock, so external calls made by a recipient cannot re-enter `VaultExecutor` while the active plan is executing against its point-in-time balance evaluation.                                                                      |
| 2026-08-12 | Place the public landing page and documentation foundation under `website/`.              | Next.js owns the public presentation layer while Fumadocs owns MDX content, search, and LLM exports; package-local commands, deployment configuration, and deferred website work remain in `website/AGENTS.md`.                                                        |
| 2026-08-13 | Keep deployment URL resolution server-only and separate it from public client links.      | `VERCEL_URL` is available during server builds but is not a browser-facing variable; importing the site URL config into the client caused deployed landing-page hydration to fail, so repository and X links live in `website/src/lib/site-links.ts`.                  |
| 2026-08-13 | Add the Phase 1 concept documentation surface under `website/content/docs/`.              | The first docs pass covers the current MVP's strategy, Mandates, Vaults, Action Plans, decisions, delegation, Preflight, and records; enforcement, execution, reference, and roadmap sections remain for later phases.                                                 |
| 2026-08-13 | Add Phase 2 enforcement and execution documentation under `website/content/docs/`.        | The docs now explain the contract enforcement path, signatures, nonces, escalation, revocation, transaction lifecycle, X Layer testnet evidence, and manifest-driven deployment wiring; guides, reference, and roadmap sections remain.                                |
| 2026-08-13 | Add Phase 3 integrator guides and contract reference pages under `website/content/docs/`. | The docs now include read-only `cast` inspection, raw Action Plan signing, evidence inspection, exact rule and action shapes, evaluator failures, and event semantics; they intentionally do not imply a Grantline SDK, API, indexer, or production valuation service. |
| 2026-08-13 | Keep an ordered registry for filename-matched website deployment copies.                   | The documentation maps explicit labels to `website/data/deployments/` files, so new networks have intentional names and order while Vercel or Docker builds scoped to `website/` remain self-contained. |

## Working-memory rules

Update this file after a material architecture, boundary, terminology, network, or workflow decision. Record what changed, why it changed, and what implementation or documentation it affects. Update the nearest nested `AGENTS.md` for package-local changes, and keep the current status and next handoff accurate.

Never put private keys, seed phrases, API tokens, or other secrets in these files. Describe the variable name and safe setup location instead.
