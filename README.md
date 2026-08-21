# Grantline

**Programmable financial authority for AI agents.**

Grantline lets you give an AI agent permission to use capital **without giving it unrestricted control of a wallet**.

An agent proposes an action. Grantline checks that action against the authority the owner gave it. Only authorised actions can reach the controlled funds.

> **AI proposes. Mandate authorises.**

[Website](https://grantline.xyz) · [Documentation](https://grantline.xyz/docs) · [Contracts](contracts/README.md) · [X](https://x.com/usegrantline) · [Apache-2.0 licence](LICENSE)

> **Testnet software:** Grantline is under active development and is not intended for unrestricted production capital.

---

## Why Grantline?

AI agents can make payments, manage treasury, execute trades, and coordinate other agents.

A wallet key gives an agent broad control. Most workflows need narrower authority.

You may want an agent to:

- spend up to a certain amount;
- keep a minimum reserve in a Vault;
- operate only during a certain period;
- escalate larger actions to a human;
- delegate narrower authority to another agent; and
- lose that authority immediately when revoked.

Grantline makes those boundaries part of the execution path.

The agent decides **what it wants to do**.

Grantline decides **whether it is authorised to do it**.

## How it works

```
Agent signs an Action Plan
            │
            ▼
   Grantline evaluates it
            │
      ┌─────┼─────┐
      ▼     ▼     ▼
   ALLOW ESCALATE DENY
      │     │
      │     ▼
      │  Human review
      │     │
      └─────┘
            │
            ▼
          Vault
```

The agent controls a signing key, not the Vault. Grantline keeps custody and authorisation separate: a Grantline-owned Vault holds Vault capital, while the agent’s proposal must pass the current Mandate, inherited authority, validity, nonce, and Preflight checks.

`ALLOW`, `ESCALATE`, and `DENY` are authorisation outcomes. An allowed plan can still fail during downstream execution, and an escalation can remain pending or be denied after controller review.

### Vault

A **Vault** holds the capital.

The agent does not control the Vault directly. It controls a signing key that can propose actions.

### Mandate

A **Mandate** defines the agent's authority.

It can restrict things like:

```
Maximum transaction
Validity period
Minimum Vault reserve
Escalation behaviour
Delegation
Pause / revocation
```

### Action Plan

An **Action Plan** is the exact action the agent wants to perform.

For example:

```
Transfer 2 native tokens
```

or:

```
Swap 1 native token for USDC
```

The agent signs that proposal.

### Evaluation

Grantline checks the proposal against the agent's current Mandate, inherited authority, Vault state, validity, nonce, and applicable Preflight rules.

The result is one of three outcomes:

**`ALLOW`** — the action is authorised.

**`ESCALATE`** — a controller must review the proposal.

**`DENY`** — the action is outside the agent's authority.

An `ALLOW` is an authorisation decision, not a guarantee that downstream execution will succeed.

## Example

Imagine a company gives an AI treasury agent access to a Vault.

Its Mandate says:

```
Max transaction:    10 native tokens
Minimum reserve:    20 native tokens
Human approval:     above 7 native tokens
Delegation:         allowed
```

The agent proposes a 3-token transfer:

```
3-token transfer
      ↓
Mandate passes
      ↓
Reserve passes
      ↓
ALLOW
      ↓
Execute
```

Then it proposes an 8-token transfer:

```
8-token transfer
      ↓
ESCALATE
      ↓
Controller review
      ↓
Approve / Reject
```

If it proposes something outside its authority entirely:

```
Proposal
   ↓
DENY
```

The agent may still want to perform the action.

Its signature may still be valid.

But it does not have the authority.

That distinction is the core of Grantline.

## Delegated authority

Mandates can delegate narrower authority to other agents.

```
Owner
└── Treasury Agent
    └── Execution Agent
        └── Payments Agent
```

For example:

```
Treasury Agent
└── up to 50 native tokens

Execution Agent
└── up to 10 native tokens

Payments Agent
└── up to 2 native tokens
```

A child agent can receive **less authority than its parent, never more**.

This makes it possible to build specialised agent organisations while keeping financial authority bounded.

## Human escalation

Some actions should not be automatically allowed or rejected.

Grantline can instead require explicit controller approval.

```
Agent proposal
      ↓
  ESCALATE
      ↓
Controller review
      ↓
Approve / Deny
```

Approval applies to that specific proposal.

Before execution, Grantline re-evaluates the current state. Approval does not permanently expand the agent’s authority.

## Architecture

```
                    Grantline
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
MandateRegistry  MandateEvaluator  EscalationManager
        │               │               │
        └───────────────┼───────────────┘
                        ▼
                  VaultExecutor
                        │
                        ▼
                      Vault
```

- **Grantline** — public protocol entry point.
- **MandateRegistry** — authority, delegation, and nonce state.
- **MandateEvaluator** — evaluates Action Plans against current rules.
- **EscalationManager** — stores controller-reviewed proposals.
- **VaultExecutor** — executes authorised plans.
- **Vault** — holds controlled capital.
- **GrantlineAdmin** — coordinates validated protocol administration and upgrades.

For the full contract architecture, see [`contracts/README.md`](contracts/README.md).

## What's here today

The repository currently includes:

- Solidity contracts built with Foundry;
- Vault custody;
- Mandates and delegated authority;
- EIP-712 signed Action Plans;
- `TRANSFER` and `SWAP` action types;
- `ALLOW`, `ESCALATE`, and `DENY`;
- controller-reviewed escalation;
- nonce-based replay protection and targeted cancellation;
- pause, revocation, and reserve Preflight checks;
- atomic multi-action execution;
- indexed Vault, Mandate, and Escalation reads;
- deployment and verification tooling;
- a Next.js website and browser demo; and
- an X Layer testnet deployment.

Some capabilities exist in the current source but are not enabled in the tracked X Layer deployment. The deployment manifest is the source of truth for what is live there. The current testnet deployment has SWAP and native-asset USD valuation disabled, so the browser demo exercises native-asset flows.

The current contract suite has 185 passing tests covering authority boundaries, delegation, custody isolation, execution atomicity, escalation transitions, pause and revocation, nonce cancellation, upgrades, indexed reads, deployment verification, SWAP validation, native-USD valuation, and fuzzed plan properties.

## Try the demo

The browser demo lives at:

**https://grantline.xyz/app**

You can use it to explore the current flow around:

- connecting a wallet;
- creating and funding Vaults;
- creating and managing Mandates;
- inspecting effective authority;
- signing native transfer Action Plans; and
- reviewing escalations.

The demo uses testnet contracts. The connected wallet submits transactions and pays gas. The configured demo agent can sign Action Plans through the server-side signing route, but its private key must remain server-only.

You need testnet OKB to pay transaction fees and fund a Vault. Get it from the [X Layer testnet faucet](https://web3.okx.com/xlayer/faucet/xlayerfaucet).

To run the website locally:

```
cd website
bun install
cp .env.example .env.local
```

Set `NEXT_PUBLIC_DEMO_AGENT_ADDRESS` to the valid public Ethereum address of the configured demo agent before starting the app. The browser app requires this value. If server-side demo signing is enabled, set `DEMO_AGENT_PRIVATE_KEY` in `.env.local` and never expose it through a `NEXT_PUBLIC_` variable.

Then start the development server:

```
bun run dev
```

## Repository

```
grantline/
├── contracts/     Solidity protocol, tests, scripts, and deployments
├── website/       Product site, browser demo, and documentation
├── BRIEF.md       Product brief
├── AGENTS.md      Project working memory
├── LICENSE        Apache License 2.0
└── README.md
```

### Contracts

```
cd contracts

forge fmt --check
forge build
forge test
```

The local end-to-end flow is in `contracts/script/run-local.sh`. It starts from a fresh deployment and requires the test accounts described in `contracts/AGENTS.md`.

### Website

```
cd website

bun install
bun run dev
bun run lint
bun run typecheck
```

Read the nearest `AGENTS.md` before changing either package. The package files contain the commands, deployment assumptions, environment variables, and boundaries that are too detailed for this overview.

## X Layer testnet

The tracked deployment targets X Layer testnet, chain ID `1952`.

- RPC: [X Layer testnet RPC](https://testrpc.xlayer.tech/terigon)
- Explorer: [OKX X Layer testnet explorer](https://web3.okx.com/explorer/x-layer-testnet)
- Grantline proxy: `0x77324b24a9290da85217b0d22925c5d9034b2062`
- Protocol admin: `0x64fe1ad6c591615dd3f0fc640c92ef75365a023d`
- Deployment manifest: [`contracts/deployments/xlayer-testnet.json`](contracts/deployments/xlayer-testnet.json)

The manifest records the deployed addresses, implementation identifiers, runtime hashes, versions, wiring, and configured dependencies. The manifest reads dynamic Vault state from the chain rather than copying it.

## What Grantline is not

Grantline is not an AI investment model.

It does not decide whether buying, selling, paying, or allocating capital is a good idea.

It governs whether the agent has the authority to perform the action.

```
Agent:     "I want to do this."

Grantline: "Are you allowed to?"
```

Grantline puts that authority check in the enforced execution path.

## Where this goes

Future work includes:

- an SDK and public API;
- richer policy types;
- Guardians for external-condition checks;
- destination and capability policies;
- sponsored execution and relaying;
- indexing and activity history;
- assembled Decision Receipts; and
- richer agent organisations and authority structures.

The question Grantline is trying to answer is simple:

> **When an autonomous agent wants to move capital, what is it actually authorised to do?**

## Licence

Grantline is licensed under the [Apache License 2.0](LICENSE).

Third-party dependencies, libraries, and assets remain subject to their own licences and terms.

<p align="center">
  <strong>Give agents autonomy. Keep authority bounded.</strong>
</p>
