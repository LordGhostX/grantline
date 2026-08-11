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

The repository contains the product brief, a static landing-page prototype, and the first working contracts loop. The contracts workspace now has the Vault, Mandate registry, typed ActionPlan and signatures, read-only evaluation, executor, shared nonce replay protection, and onchain execution records. Local tests pass, and a fresh X Layer testnet registry/evaluator/executor stack is wired to the deployed Vault; USD valuation is explicitly skipped on testnet while native limits remain active. Relayer, indexing, Decision Receipt assembly, SDK, API, and demo application work remain deferred.

The next implementation step is to exercise the deployed end-to-end loop with a signed transfer plan, then extend action-specific rules only when the product needs them.

## Decision log

| Date       | Decision                                          | Reason and impact                                                                                                                 |
| ---------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Keep blockchain files under `contracts/`.         | The repository will also contain a website, SDKs, and API, so root-level tooling would make ownership and commands ambiguous.     |
| 2026-08-11 | Use `AGENTS.md` as the working-memory convention. | Agents discover the file automatically, and nested files can document package-local boundaries without bloating the root context. |

## Working-memory rules

Update this file after a material architecture, boundary, terminology, network, or workflow decision. Record what changed, why it changed, and what implementation or documentation it affects. Update the nearest nested `AGENTS.md` for package-local changes, and keep the current status and next handoff accurate.

Never put private keys, seed phrases, API tokens, or other secrets in these files. Describe the variable name and safe setup location instead.
