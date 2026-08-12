# Grantline Working Memory

## Purpose

Grantline is programmable financial authority for AI agents. The agent proposes an action, while Grantline determines whether that action is authorised under an active Mandate and its surrounding conditions.

This file is the project-wide working memory for future agents and contributors. Keep implementation details in the nearest package-level `AGENTS.md` and keep this file focused on shared context, boundaries, decisions, and handoffs.

## Current repository map

```text
.
├── AGENTS.md                 # Project-wide working memory
├── BRIEF.md                  # Product brief
├── index.html                # Temporary GitHub Pages landing page
├── plans/                    # Local, ignored planning documents
└── contracts/                # Foundry workspace and future Grantline contracts
    ├── AGENTS.md
    ├── foundry.toml
    ├── src/
    ├── test/
    ├── script/
    └── lib/
```

Future application boundaries are expected to be `website/` for the Next.js landing, demo, and docs surfaces, `sdk/` for agent-facing client libraries, and `api/` for backend orchestration and records. Create a local `AGENTS.md` when each package is introduced instead of putting package-specific details here.

## Product invariants

- The agent decides what it wants to do; Grantline decides whether it is allowed to do it.
- Vault capital must be unreachable through an agent-controlled bypass path.
- `ALLOW`, `ESCALATE`, and `DENY` are authorisation outcomes, not execution outcomes.
- An authorised action can still fail during downstream execution, and that must remain distinguishable from `DENY`.
- Delegated authority may become narrower, never broader, than its parent authority.
- Revocation preserves historical lineage while preventing future authority use.
- Public-facing product copy uses UK English, including `authorisation`, `authorised`, and `tokenised`.

## Current status

The repository contains the product brief, a static landing-page prototype, and the working contracts loop. The contracts workspace now has the Vault, nested mandate rules, typed ActionPlan and signatures, `ALLOW`/`ESCALATE`/`DENY` evaluation, full-plan escalation storage, owner approval or denial, shared nonce replay protection, executor re-evaluation, onchain execution records, and deployment verification with runtime-hash validation. All local tests pass. The fresh X Layer enforcement stack has been verified end to end for Phase 1; the tracked manifest remains that live Phase 1 stack until the Phase 2 contracts are explicitly deployed. Sponsored transaction submission, offchain indexing, behavioural history and receipt assembly, SDK, API, and demo application work remain deferred.

Phase 2 ESCALATE is implemented and locally verified. The next operational step is a deliberate fresh-stack X Layer deployment because the registry, evaluator, manager, executor, and Vault wiring are non-upgradeable. Sponsored submission remains deferred because the integration evidence uses the agent as the actual transaction submitter; users currently submit the transaction and pay its gas directly.

## Decision log

| Date       | Decision                                                                             | Reason and impact                                                                                                                                                        |
| ---------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2026-08-11 | Keep blockchain files under `contracts/`.                                            | The repository will also contain a website, SDKs, and API, so root-level tooling would make ownership and commands ambiguous.                                            |
| 2026-08-11 | Use `AGENTS.md` as the working-memory convention.                                    | Agents discover the file automatically, and nested files can document package-local boundaries without bloating the root context.                                        |
| 2026-08-11 | Keep deployment identity in a tracked contracts manifest.                            | Deployment scripts need one reviewable source for addresses, dependency wiring, runtime hashes, and current Vault authority.                                             |
| 2026-08-12 | Store mandate policy in nested rules and make limit overruns optionally escalatable. | Native and USD limits stay adjacent to their flags, while the evaluator can route configured overruns through explicit owner approval without weakening hard-deny rules. |
| 2026-08-12 | Store complete escalated plans in a dedicated manager.                               | Approval and later execution remain decoupled from the original submitting process, while the executor re-evaluates current mandate state before moving capital.         |
| 2026-08-12 | Use aggregate native/USD amount ranges for mandate transaction bounds.               | Minimums and maximums are denomination-aware, each bound can be disabled with zero, and transaction minimums remain separate from future Vault liquidity rules.          |
| 2026-08-12 | Keep Mandate updates live and allow denial after revocation.                         | Current rules are checked at execution, revocation blocks approval and execution, while the Vault owner can still close pending revoked escalations with a denial.       |

## Working-memory rules

Update this file after a material architecture, boundary, terminology, network, or workflow decision. Record what changed, why it changed, and what implementation or documentation it affects. Update the nearest nested `AGENTS.md` for package-local changes, and keep the current status and next handoff accurate.

Never put private keys, seed phrases, API tokens, or other secrets in these files. Describe the variable name and safe setup location instead.
