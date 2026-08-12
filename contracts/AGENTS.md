# Contracts Working Memory

## Purpose and boundary

This directory owns Grantline's Solidity contracts, Foundry tests, deployment scripts, and contract-local development configuration. It is the enforcement boundary for Vault custody, Mandates, Actions, authorisation decisions, execution, delegation, revocation, and onchain Records as those features are implemented.

## Layout

```text
contracts/
├── AGENTS.md
├── .env.example             # Safe configuration template; no secrets
├── foundry.toml             # Foundry profiles and RPC aliases
├── deployments/              # Tracked deployment manifests and runtime hashes
├── src/                     # Production Solidity contracts
├── test/                    # Foundry unit and invariant tests
├── script/                  # Deployment and operational scripts
└── lib/                     # Local Foundry dependencies, ignored by Git
```

## Environment

The first remote target is X Layer testnet. The official configuration currently used here is:

- Network: X Layer testnet
- Chain ID: `1952`
- Gas token: `OKB`
- Primary RPC: `https://testrpc.xlayer.tech/terigon`
- Explorer: `https://web3.okx.com/explorer/x-layer-testnet`

Validation on 2026-08-11 confirmed chain ID `1952` and block access through the X Layer testnet RPC.

Copy `.env.example` to `.env` for local use. Keep private keys only in the untracked `.env` or in the environment of the command that needs them. Use dedicated burner accounts for testnet work; never use a production key.

## Commands

Run these commands from `contracts/`:

```sh
forge test
forge build
anvil
cast chain-id --rpc-url http://127.0.0.1:8545
cast chain-id --rpc-url "$XLAYER_TESTNET_RPC_URL"
cast block-number --rpc-url "$XLAYER_TESTNET_RPC_URL"
```

Load local variables before using the named X Layer aliases or shell variables:

```sh
set -a
source .env
set +a
```

Every script reads `DEPLOYMENT_MANIFEST_PATH`, parses the manifest's expected chain ID, and aborts before broadcasting when it differs from `block.chainid`; the tracked X Layer testnet manifest is `deployments/xlayer-testnet.json`. The manifest is the source of truth for contract addresses, owners, current authority, dependency wiring, evaluator settings, deployment transactions, and runtime code hashes, while `.env` supplies the RPC, explorer, manifest locator, deployer key, and integration-agent key. Deployment scripts never write the manifest automatically, because an operator must record the broadcast result and code hash only after the transaction succeeds.

## Current status and handoff

The workspace contains the Foundry toolchain smoke test, the `DeploymentProbe`, the `Vault`, the `MandateRegistry`, `MandateEvaluator`, `EscalationManager`, and `VaultExecutor`. The local Foundry suite covers 94 tests with Foundry 1.7.1; Anvil responds on chain ID `31337`, and the X Layer RPC responds on chain ID `1952`.

The active X Layer testnet stack is recorded in `deployments/xlayer-testnet.json`, including its shared-nonce registry, evaluator, executor, authority assignment, exact runtime hashes, and authority transaction. That manifest is still the Phase 1 stack; the Phase 2 deployment scripts expect a fresh `EscalationManager` and executor wiring, but no live broadcast has replaced the manifest yet. Mandates contain nested `MandateRules` with aggregate `minNativeAmount`/`maxNativeAmount` and `minUsdAmount`/`maxUsdAmount` bounds, with one escalation flag beside each denomination's bounds. Zero disables an individual bound, and a minimum only applies when that denomination is present in the plan. Native values use raw OKB base units, while USD values use 1e18-scaled USD units. The current evaluator has no USD provider and allows unavailable valuation on testnet; if a provider supplies only some quotes, every available quote still contributes to the enforced subtotal, `usdLimitSkipped` records that at least one action was unvalued, and the USD minimum is skipped while the available subtotal can still exceed the maximum. `ActionTypes` defines an atomic, ordered ActionPlan with versioned high-level action payloads; only `TRANSFER` is currently defined, and raw Vault calldata is intentionally outside the agent-facing format. `ActionSignature` provides EIP-712 hashing and low-s malleability-checked signer recovery. `MandateEvaluator` returns `ALLOW`, `ESCALATE`, or `DENY` after validating the complete plan and aggregate amount bounds. `EscalationManager` stores the full signed plan for an escalated digest, accepts permissionless submission, restricts approval or denial to the current Vault owner, and reserves its nonce until execution or terminal denial. `VaultExecutor` handles normal allowed plans and re-evaluates approved escalations before translating native and ERC-20 transfers into atomic Vault calls. Vault token custody rejects non-contract token targets before making or recording a transfer call. Offchain relaying, indexing, and receipt assembly remain deferred.

## Action format

The agent-facing proposal uses readable intent fields rather than Solidity calldata:

```json
{
  "mandateId": "1",
  "agent": "0xAgent",
  "nonce": "0",
  "deadline": "0",
  "actions": [
    {
      "type": "transfer",
      "version": 1,
      "asset": "native",
      "to": "0xRecipient",
      "amount": "1000000000000000000"
    }
  ]
}
```

`actions` is an ordered, atomic plan. `nonce` is a Grantline-managed proposal identifier scoped to the mandate and agent; it does not force strict execution order. `deadline` is an absolute Unix timestamp in seconds, with `0` meaning no expiry. The evaluator compares it with `block.timestamp`, which is the standard chain clock but can have limited validator-controlled drift, so callers should use a safety margin rather than depend on an exact second-level boundary. Transaction inclusion delay matters alongside timestamp drift, and we do not assume a precise X Layer drift budget: use roughly 30–60 seconds for ordinary actions and 1–2 minutes for relayed or higher-value actions. These are operating defaults, not contract-enforced constants. The `type` and `version` select the typed decoder, and the currently supported `transfer` format is version `1`; unsupported versions are rejected until a matching evaluator and executor decoder are introduced. `native` maps to the zero address internally; token amounts use raw base units. Typed parameters are translated into validated Vault calls, while raw calldata remains outside the agent-facing format.

## Agent signatures

`ActionSignature` uses EIP-712 with domain name `Grantline`, domain version `1`, the active chain ID, and the verifying-contract address. The signed digest covers the complete ActionPlan, including the ordered action array and each action's exact typed parameter bytes. A valid signature must recover to `ActionPlan.agent`; malformed, non-27/28, or high-`s` signatures return an invalid signer. The verifying contract is supplied by the eventual authority/execution boundary, so signatures are not portable across chains or contracts.

## Mandate evaluation

`MandateEvaluator` returns a structured `ALLOW`, `ESCALATE`, or `DENY` result after checking Mandate existence and activity, agent binding, EIP-712 signature, deadline, non-empty actions, supported action version `1`, non-empty parameters, and transfer recipients and amounts. Native and USD rules apply to the aggregate amount of the complete `TRANSFER` plan. Native minimums are skipped for token-only plans, while USD minimums require complete available valuation; an unavailable USD quote in testnet skip mode sets `usdLimitSkipped` and skips the USD minimum. Available USD values still accumulate and can exceed the configured maximum even when another action is unvalued. Any violated bound becomes `ESCALATE` only when its denomination's escalation flag is enabled; a hard violation remains `DENY`. Live evaluator deployments require a provider and fail closed when it cannot quote. These transaction minimums constrain plan size and do not represent minimum Vault liquidity after execution. Mandate updates apply immediately to normal execution and approved escalations because evaluation reads current rules at execution time; revocation returns `MANDATE_INACTIVE` and blocks approval and execution.

## Vault execution

`VaultExecutor` is the execution boundary above the low-level `Vault`. It re-runs `MandateEvaluator`, confirms the Mandate points to the supplied Vault, and translates each supported `TRANSFER` action into a `Vault.execute` call. Native transfers target the recipient directly; token transfers call ERC-20 `transfer` through the Vault. The executor accepts the standard empty or `true` ERC-20 return conventions and rejects false, malformed, or missing token targets. Normal execution accepts only `ALLOW`; approved escalations are loaded by digest from `EscalationManager`, re-evaluated against current rules, and execute only if they are still `ALLOW` or `ESCALATE`.

The Vault owner must explicitly set the executor as the Vault authority. Before broadcasting, `ConfigureVaultAuthority` verifies the manifest chain, runtime hashes, Vault owner and current authority, executor evaluator and manager, manager evaluator, evaluator registry, and evaluator USD configuration. `VerifyDeployment` performs the same live read-only checks without broadcasting and rejects any nonzero Vault authority that is not the manifest executor, so an EOA or bypass contract cannot be recorded as an apparently valid deployment. When rotating authority, update the manifest only after the new executor is deployed, verified, and the authority transaction succeeds; until then, the old authority remains the expected value and a failed or misdirected configuration cannot be hidden by editing the record first. The executor does not configure authority and cannot execute against a different Vault than the one stored in the Mandate. If evaluation fails, the executor reverts before calling the Vault; if a later downstream action fails, the whole executor transaction reverts, so earlier actions are rolled back. `MandateRegistry` consumes each `(mandateId, agent, nonce)` once after evaluation and before external calls, and checks the Vault's current authority, so a successful plan cannot be replayed through a replacement executor while a failed plan's nonce consumption rolls back with the transaction. `EscalationManager` reserves a nonce as soon as it stores an escalated plan, so a pending, approved, or denied escalation cannot be bypassed by submitting the same nonce through normal execution. Different nonces remain independently executable and do not require strict ordering. After revocation, the owner may still deny pending escalations to clear operational backlog, but cannot approve them; approved escalations remain approved for history while current evaluation prevents execution.

## Onchain records

Contracts emit events rather than storing large human-readable records. MandateRegistry events cover successful Mandate lifecycle changes, `EscalationManager` events cover successful submission, approval, denial, and execution status changes, Vault events cover successful custody and low-level call attempts, and `VaultExecutor.ActionPlanExecuted` records the digest, Mandate, agent, Vault, nonce, aggregate native amount, quoted USD subtotal, whether any USD valuation was skipped, and action count after a complete plan succeeds. The manager stores the full signed escalated plan because later execution must not depend on the original submitting process. Failed evaluations, revoked-mandate approvals, and failed executions revert with error data and receipt status `0`; their transaction events do not persist. An approved escalation that fails current re-evaluation remains `APPROVED`, while a pending revoked escalation can still transition to `DENIED` through the owner action.

## Deferred work

- [ ] Build a minimal offchain relayer after the contract execution loop is complete. It should accept a signed ActionPlan, submit `VaultExecutor.execute` with a funded EOA, and report the transaction receipt. It must remain a gas-paying caller only; `VaultExecutor` and the Vault authority configuration remain the enforcement boundary.
- [ ] Build offchain indexing and Decision Receipt assembly. It should combine signed ActionPlans, evaluator results, revert data, transaction receipts, Mandate events, Vault events, and `VaultExecutor` events into a queryable behavioural history without moving the enforcement boundary offchain.

## Current X Layer deployment

`deployments/xlayer-testnet.json` is the current deployment record. Run `forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url xlayer_testnet` after loading `.env` to confirm the live addresses, runtime hashes, owner, authority, dependency wiring, zero USD provider, enabled testnet skip mode, and registry state. The deployer key is intentionally not recorded.

### Phase 1 integration evidence

The fresh stack was exercised on X Layer testnet with the deployer as Vault owner and the separately funded `BURNER_AGENT_PUBLIC_KEY` as agent. The agent submitted the execution transactions directly; no relayer was used. Deployment addresses, runtime hashes, and deployment transactions remain authoritative in the manifest.

| Operation                 | Transaction                                                          | Result                                                                                                            |
| ------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Deposit `0.003 OKB`       | `0x342945c1272cd1ab9be7fffc6e3c9d99d4519e4a9cd57cc617307e5016c25a92` | Vault balance became `0.003 OKB`.                                                                                 |
| Create Mandate `1`        | `0xd60f7d71ad17a52eac50f82f9ad800d91b7dd19671bf291a26edcefe907e54dc` | Agent `0x648aC3F9297d59089B02a6091DA6dd76902a785B`; native limit `0.001 OKB`; USD limit disabled.                 |
| Agent success, nonce `1`  | `0xe42e5b9244ed57a2daa98121d2993f08feb3d65443249397e5b94891d71b4755` | Status `1`; `ActionPlanExecuted` emitted; `0.001 OKB` returned to the deployer; Vault balance became `0.002 OKB`. |
| Agent denial, nonce `2`   | `0xda8796127aba361e719204ca4772174f6cd2df3d6afdef073f6fc67a26860bb3` | Status `0`; `EvaluationDenied(TRANSACTION_LIMIT_EXCEEDED, 0)`; no logs, no movement, nonce `2` unused.            |
| Agent replay of nonce `1` | `0x19eae71a2c1515621e3263e4a0980f6b859a277c530252ce1a89a8c31ed028ca` | Status `0`; `NonceAlreadyUsed`; no logs, Vault remained at `0.002 OKB`, nonce `1` stayed consumed.                |
| Owner withdrawal          | `0x01f4b5cbf334273bb0a49ef2c3e77f416b3151b5ae021abc4c5bce899f081dd4` | Status `1`; `0.002 OKB` withdrawn by the deployer; final Vault balance is zero.                                   |

The successful plan digest was `0x051db329bd0ea776a9cb8438ee7069ae8273dca6eb9447a5283a4a961344698`. The reusable flow is in `script/TestnetIntegration.s.sol`; expected-revert calldata is generated locally and submitted with an explicit gas limit so X Layer records the failed receipts.

## Contract decisions

| Date       | Decision                                                                                      | Reason and impact                                                                                                                                                                                           |
| ---------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Use Foundry + Anvil.                                                                          | This keeps Solidity tests and local execution fast while supporting direct X Layer deployment and verification.                                                                                             |
| 2026-08-11 | Configure local and testnet networks, but do not configure mainnet deployment.                | The first proof must be safe and reproducible; mainnet access is unnecessary for the MVP environment setup.                                                                                                 |
| 2026-08-11 | Keep the first smoke test free of Grantline logic.                                            | It proves the toolchain independently, so later contract failures are not confused with environment failures.                                                                                               |
| 2026-08-11 | Use a dependency-free `DeploymentProbe` before Grantline contracts.                           | It verifies signer, chain ID, broadcast, receipts, and remote reads without introducing product authority logic.                                                                                            |
| 2026-08-11 | Use one configurable Vault authority, initially unset.                                        | Owner custody remains available, while autonomous execution is impossible until a later authority contract is explicitly connected.                                                                         |
| 2026-08-11 | Represent Agents as registered EOA addresses.                                                 | A Mandate can bind directly to the signing address without introducing smart accounts or a separate identity lifecycle.                                                                                     |
| 2026-08-11 | Store Mandates in one sequential onchain registry.                                            | IDs, status, lifecycle history, and future indexing remain in one durable authority data layer.                                                                                                             |
| 2026-08-11 | Start with a single optional transaction limit.                                               | `transactionLimit == 0` means disabled, which lets a mandate omit the constraint while the enforcement path is designed separately.                                                                         |
| 2026-08-11 | Represent agent proposals as ordered, atomic ActionPlans.                                     | Agents submit high-level typed intent; a later adapter can translate each action into validated Vault calls without exposing Solidity calldata.                                                             |
| 2026-08-11 | Version each Action payload independently.                                                    | `actionType + version` selects decoding rules, so future action types or changed transfer semantics do not reinterpret existing payloads.                                                                   |
| 2026-08-11 | Use Grantline-managed proposal nonces and absolute Unix-second deadlines.                     | Nonces identify one execution slot without forcing strict ordering, while deadlines allow pending escalations to expire.                                                                                    |
| 2026-08-11 | Store ActionPlan nonce consumption in MandateRegistry and gate it to current Vault authority. | The EVM transaction nonce belongs to the submitting wallet, and shared state prevents a signed plan from replaying after executor replacement.                                                              |
| 2026-08-11 | Sign ActionPlans with EIP-712.                                                                | Agents sign readable intent while the digest binds the complete ordered plan to chain ID and verifying contract, preventing cross-domain replay.                                                            |
| 2026-08-11 | Keep Mandate evaluation separate from decision aggregation.                                   | The evaluator returns the first structured failure so later Guardian and Preflight checks can compose before ALLOW, DENY, or ESCALATE is produced.                                                          |
| 2026-08-11 | Keep `transactionLimit` as the native OKB cap and add USD as a separate limit.                | Native amounts remain directly enforceable in raw base units, while USD-valued exposure gets its own independently configurable constraint.                                                                 |
| 2026-08-11 | Add an independent USD transaction limit for current transfers.                               | Native caps remain raw OKB limits, while a configured valuation provider can aggregate transfer value in USD; testnet may explicitly skip unavailable quotes.                                               |
| 2026-08-11 | Keep Vault custody unchanged and execute through a separate VaultExecutor.                    | Vault remains a simple authority-controlled custody primitive, while action translation and execution failure handling can evolve independently.                                                            |
| 2026-08-11 | Revert the complete executor transaction when a downstream action fails.                      | A plan is atomic, so partial capital movement cannot be mistaken for successful execution.                                                                                                                  |
| 2026-08-11 | Enforce every available USD quote when some valuations are unavailable.                       | Skip mode marks incomplete valuation without discarding or bypassing the quoted subtotal, so authorisation no longer depends on action order.                                                               |
| 2026-08-11 | Validate chain and dependency identity before every authority broadcast.                      | Scripts fail before signing on a chain mismatch, and Vault authority changes require the expected owner, current authority, executor, evaluator, and registry.                                              |
| 2026-08-11 | Use a tracked deployment manifest as the operational trust source.                            | Addresses, runtime hashes, dependency wiring, and current authority stay together, so scripts do not trust independently editable address environment variables.                                            |
| 2026-08-11 | Use `block.timestamp` for ActionPlan deadlines and accept the timestamp lint.                 | Onchain expiry needs the chain's standard Unix-second clock; deadlines are guardrails with caller-provided safety margins, not exact wall-clock timers.                                                     |
| 2026-08-11 | Reject unsupported Action versions at both evaluation and execution.                          | The current transfer decoder supports version `1` only, so a future payload cannot be authorised and then silently decoded with old semantics.                                                              |
| 2026-08-12 | Add owner-approved escalation with nested per-limit flags.                                    | A limit overrun becomes `ESCALATE` only when its denomination is configured for escalation; the full signed plan is stored by digest, owner approval is explicit, and execution re-evaluates current rules. |
| 2026-08-12 | Reserve escalation nonces before approval and consume them only after execution.              | Pending or denied plans cannot be bypassed through a later normal `ALLOW` path, while a failed approved execution can still be retried because the transaction rolls back.                                  |
| 2026-08-12 | Replace max-only limits with aggregate native/USD amount ranges.                              | Minimums and maximums use compact denomination-aware names, zero disables each bound, range ordering is validated in the registry, and minimums remain distinct from future liquidity rules.                |
| 2026-08-12 | Re-evaluate current Mandate rules at execution and allow denial after revocation.             | Tightening blocks normal or approved execution, loosening can reopen an approved escalation, revocation blocks approval/execution, and the owner can still deny pending revoked escalations.                |

Update this file whenever contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
