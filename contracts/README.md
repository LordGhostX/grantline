# Grantline Contracts

Grantline is the onchain financial authorisation layer for AI agents.

These contracts sit between an agent's signed intent and controlled capital:

```text
Agent signs Action Plan
        ↓
Grantline evaluates authority
        ↓
ALLOW / ESCALATE / DENY
        ↓
controlled Vault execution
```

> An agent may propose actions and sign them, but its signing key is not the authority that controls the Vault.

Grantline evaluates the agent's Mandate, inherited authority, proposal validity, nonce state, and applicable Preflight rules before autonomous execution can reach Vault capital.

For the broader protocol model, see [Grantline documentation](https://grantline.xyz/docs).

---

## Start here

If you are trying to understand the system:

1. `src/Grantline.sol`
2. `src/GrantlineTypes.sol`
3. `src/ActionTypes.sol`
4. `src/MandateRegistry.sol`
5. `src/MandateEvaluator.sol`
6. `src/VaultExecutor.sol`
7. `src/Vault.sol`

If you are modifying the contracts, also read:

- `AGENTS.md` — architecture, invariants, deployment state, and implementation notes
- `test/` — executable expectations
- `script/` — deployment and integration flows
- `deployments/` — tracked deployment identity and wiring

Do not infer live network capabilities solely from `src/`. The source tree can be ahead of deployed contracts.

---

## Core model

Grantline has four core primitives.

### Mandate — authority

Defines what an agent may do against a Vault.

Mandates can constrain:

- amounts;
- validity windows;
- Preflight reserve boundaries;
- escalation behavior;
- USD-denominated limits;
- delegation.

Delegated Mandates may narrow inherited authority but cannot expand it.

```text
effective authority
    =
current Mandate
    ∩
active ancestor boundaries
```

### Action Plan — intent

The exact proposal signed by an agent.

```solidity
struct ActionPlan {
    uint256 mandateId;
    address agent;
    uint256 nonce;
    uint256 deadline;
    Action[] actions;
}
```

Current action types:

```text
TRANSFER
SWAP
```

Action Plans use Grantline's EIP-712 domain and `ActionSignature.sol`.

Changing the plan changes the signed commitment.

### Vault — custody

A Vault holds capital.

The agent does not own the Vault or receive unrestricted Vault authority.

`VaultExecutor` is the autonomous execution authority, while the controller retains custody and administration through `Grantline`.

### Decision — authorisation

Evaluation returns:

```text
ALLOW
ESCALATE
DENY
```

These are authorisation results, not transaction results.

---

## Architecture

```text
                         ┌────────────────────┐
                         │     Grantline      │
                         │   public facade    │
                         └─────────┬──────────┘
                                   │
          ┌────────────────────────┼───────────────────────┐
          ▼                        ▼                       ▼
 ┌─────────────────┐    ┌───────────────────┐   ┌──────────────────┐
 │ MandateRegistry │◄──►│ MandateEvaluator  │   │EscalationManager │
 │ authority state │    │ decision engine   │   │ controller review│
 └─────────────────┘    └─────────┬─────────┘   └────────┬─────────┘
                                  │                      │
                                  └──────────┬───────────┘
                                             ▼
                                   ┌──────────────────┐
                                   │  VaultExecutor   │
                                   └────────┬─────────┘
                                            ▼
                                       ┌─────────┐
                                       │  Vault  │
                                       └─────────┘

Grantline ──► VaultFactory ──► Vault proxies
Grantline ──► configured swap adapters
```

`GrantlineAdmin` coordinates protocol configuration and upgrades.

---

## Contract map

| Contract                | Responsibility                                           |
| ----------------------- | -------------------------------------------------------- |
| `Grantline.sol`         | Main public facade                                       |
| `MandateRegistry.sol`   | Mandates, delegation, lineage, nonce and authority state |
| `MandateEvaluator.sol`  | Returns ALLOW / ESCALATE / DENY                          |
| `EscalationManager.sol` | Stores and manages controller-reviewed proposals         |
| `VaultExecutor.sol`     | Connects successful authorisation to execution           |
| `Vault.sol`             | Custody boundary                                         |
| `VaultFactory.sol`      | Creates and tracks Vault proxies                         |
| `GrantlineAdmin.sol`    | Protocol administration and upgrades                     |
| `UniswapV3Adapter.sol`  | SWAP v1 execution adapter                                |
| `ActionTypes.sol`       | Canonical action structures                              |
| `ActionSignature.sol`   | EIP-712 Action Plan hashing                              |
| `GrantlineTypes.sol`    | Mandates, rules, evaluations, and escalations            |
| `ComponentTypes.sol`    | Component role identifiers                               |
| `Interfaces.sol`        | Shared interfaces                                        |
| `ProtocolAccess.sol`    | Shared protocol access and upgrade logic                 |

Protocol types should have one canonical definition.

---

## Request flow

### Evaluation

```text
Grantline.evaluate(...)
        ↓
MandateEvaluator
        ↓
MandateRegistry + Vault state
        ↓
ALLOW / ESCALATE / DENY
```

Evaluation does not move capital.

### Execution

```text
Grantline.execute(...)
        ↓
VaultExecutor
        ↓
MandateEvaluator
        ↓
MandateRegistry
        ↓
nonce consumed
        ↓
Vault
```

Action Plans execute atomically.

### Escalation

```text
Action Plan
    ↓
ESCALATE
    ↓
submitEscalation(...)
    ↓
controller approves / denies
    ↓
executeEscalated(...)
    ↓
re-evaluate current state
    ↓
Vault
```

Approval applies to the exact stored proposal and does not bypass current-state evaluation.

---

## Delegation, nonces, and revocation

Mandates form an authority tree:

```text
Root Mandate
    ↓
Child Mandate
    ↓
Grandchild Mandate
```

Descendants inherit ancestor boundaries.

Action Plans use nonces for replay protection. Pending escalations reserve their nonce, and unused unreserved nonces can be cancelled.

Mandates can be:

- paused — temporarily inactive;
- revoked — permanently inactive for future authority evaluation.

Revocation stops future use without erasing historical lineage.

---

## Where should I make a change?

| Goal                            | Start with                                     |
| ------------------------------- | ---------------------------------------------- |
| Public protocol interaction     | `Grantline.sol`                                |
| Mandate lifecycle               | `MandateRegistry.sol`                          |
| Delegation/inheritance          | `MandateRegistry.sol` + `MandateEvaluator.sol` |
| Authorisation / Preflight rules | `MandateEvaluator.sol`                         |
| Action Plan structure           | `ActionTypes.sol` + `ActionSignature.sol`      |
| Execution semantics             | `VaultExecutor.sol`                            |
| Custody behavior                | `Vault.sol`                                    |
| Escalation                      | `EscalationManager.sol`                        |
| Vault creation                  | `VaultFactory.sol`                             |
| Upgrades/admin                  | `GrantlineAdmin.sol` + `ProtocolAccess.sol`    |
| Swaps                           | `UniswapV3Adapter.sol`                         |
| Deployment                      | `script/DeployGrantline.s.sol`                 |
| Deployment validation           | `script/VerifyGrantlineDeployment.s.sol`       |
| Expected security behavior      | `test/`                                        |
| Current implementation context  | `AGENTS.md`                                    |

A change to one layer may require matching tests and deployment/verifier updates.

---

## Repository layout

```text
contracts/
├── README.md
├── AGENTS.md
├── src/
├── test/
├── script/
├── deployments/
├── lib/
├── foundry.toml
└── .env.example
```

---

## Development

The contracts use Foundry and OpenZeppelin.

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/LordGhostX/grantline.git
cd grantline/contracts
```

For an existing clone:

```bash
git submodule update --init --recursive
```

Build and test:

```bash
forge fmt --check
forge build
forge test
```

Copy the environment template when needed:

```bash
cp .env.example .env
```

Never commit private keys.

---

## Deployment

Deployment is manifest-driven through `script/DeployGrantline.s.sol`.

Tracked deployments live under:

```text
deployments/
```

Use deployment manifests as the source of truth for deployed addresses and configured capabilities.

Verify a deployment with:

```bash
forge script \
  script/VerifyGrantlineDeployment.s.sol:VerifyGrantlineDeployment \
  --rpc-url xlayer_testnet
```

The verifier checks component identity, implementations, ownership, wiring, Vault authority, adapters, and configured dependencies.

### X Layer testnet

The tracked X Layer deployment uses:

```text
Network:  X Layer testnet
Chain ID: 1952
Gas:      OKB
```

See:

```text
deployments/xlayer-testnet.json
```

The source tree currently contains capabilities that may not exist in this deployment, including SWAP v1, targeted nonce cancellation, and native-USD rules.

Always check the deployment manifest before assuming a source capability is live.

---

## Security invariants

When changing the contracts, preserve these boundaries unless intentionally redesigning the protocol:

- the agent key is not Vault authority;
- agent-led capital movement must cross authorisation;
- delegation may narrow authority, never expand it;
- authority is evaluated against current state;
- escalation approval is not an evaluation bypass;
- nonce state must remain coherent across execution and escalation;
- multi-action plans execute atomically;
- component identity and deployment wiring are security-relevant.

If something is supposed to stop capital movement, that restriction must exist in the enforced execution path, not only in documentation.

---

## Before contributing

1. Read `AGENTS.md`.
2. Identify the enforcement boundary affected.
3. Search existing tests for the behavior.
4. Update canonical protocol types rather than duplicating them.
5. Check whether deployment or verification logic also changes.
6. Test both the intended path and rejection/bypass paths.
7. Run `forge fmt --check`, `forge build`, and `forge test`.

---

## Documentation

**https://grantline.xyz/docs**

For implementation-specific working memory, use `AGENTS.md`.

---

## Status

Grantline is under active development.

Interfaces, deployment architecture, and supported policy surfaces may change as the protocol hardens.

Tracked testnet deployments are inspectable deployment evidence, not an assertion that the contracts are production-ready or audited for unrestricted production capital.
