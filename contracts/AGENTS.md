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

Every script reads `DEPLOYMENT_MANIFEST_PATH`, parses the manifest's expected chain ID, and aborts before broadcasting when it differs from `block.chainid`; the tracked X Layer testnet manifest is `deployments/xlayer-testnet.json`. The manifest is the source of truth for contract addresses, owners, current authority, dependency wiring, evaluator settings, deployment transactions, and runtime code hashes, while `.env` supplies only the RPC, explorer, manifest locator, and deployer key. Deployment scripts never write the manifest automatically, because an operator must record the broadcast result and code hash only after the transaction succeeds.

## Current status and handoff

The workspace contains the Foundry toolchain smoke test, the `DeploymentProbe`, the `Vault`, the `MandateRegistry`, `MandateEvaluator`, and `VaultExecutor`. All 70 `forge test` cases pass with Foundry 1.7.1, Anvil responds on chain ID `31337`, and the X Layer RPC responds on chain ID `1952`.

The active X Layer testnet stack is recorded in `deployments/xlayer-testnet.json`, including its shared-nonce registry, evaluator, executor, authority assignment, and exact runtime hashes. The registry remained empty during deployment. Mandates store optional native and USD per-transaction limits; `transactionLimit == 0` and `usdTransactionLimit == 0` disable their respective checks. The native limit uses raw OKB base units, while USD values use 1e18-scaled USD units. The current evaluator has no USD provider and allows unavailable valuation on testnet; if a provider supplies only some quotes, every available quote still contributes to the enforced subtotal and `usdLimitSkipped` records that at least one action was unvalued. `ActionTypes` defines an atomic, ordered ActionPlan with versioned high-level action payloads; only `TRANSFER` is currently defined, and raw Vault calldata is intentionally outside the agent-facing format. `ActionSignature` provides EIP-712 hashing and low-s malleability-checked signer recovery, and `MandateEvaluator` performs read-only Mandate, signature, deadline, action-shape, native-limit, and transfer USD-limit checks. `MandateRegistry` owns nonce consumption scoped to `(mandateId, agent, nonce)` and permits only the Vault's current authority to consume it, so executor replacement cannot reopen a used signature. `VaultExecutor` translates evaluator-approved native and ERC-20 transfers into atomic Vault calls and emits a plan-level success record. Vault token custody rejects non-contract token targets before making or recording a transfer call. Action-hash storage, adapters beyond transfers, decision aggregation, offchain indexing, Decision Receipt assembly, and relaying remain unimplemented.

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

`MandateEvaluator` returns a structured pass/fail result and stops at the first failure; it does not emit ALLOW or DENY. It checks Mandate existence and activity, agent binding, EIP-712 signature, deadline, non-empty actions, supported action version `1`, non-empty parameters, and the transfer payload's recipient and amount. A nonzero `transactionLimit` applies to the aggregate native OKB amount in raw base units. A nonzero `usdTransactionLimit` applies to the aggregate USD value of current `TRANSFER` actions, quoted by the configured `IUsdValueProvider`; native actions use the zero address as the asset identifier, and the provider handles token decimals and pricing. Testnet evaluator deployments may allow unavailable valuation, but an unavailable action only sets `usdLimitSkipped`: it never clears the subtotal or prevents later available quotes from enforcing the limit. `usdAmount` therefore contains the quoted subtotal even when `usdLimitSkipped` is true. Live evaluator deployments require a provider and fail closed when it cannot quote. Future action types will supply their own validated USD amount through action-specific rules rather than being treated as generic transfers. Future Guardian, Preflight, and decision checks should consume this result rather than be folded into the evaluator.

## Vault execution

`VaultExecutor` is the execution boundary above the low-level `Vault`. It re-runs `MandateEvaluator`, confirms the Mandate points to the supplied Vault, and translates each supported `TRANSFER` action into a `Vault.execute` call. Native transfers target the recipient directly; token transfers call ERC-20 `transfer` through the Vault. The executor accepts the standard empty or `true` ERC-20 return conventions and rejects false, malformed, or missing token targets.

The Vault owner must explicitly set the executor as the Vault authority. Before broadcasting, `ConfigureVaultAuthority` verifies the manifest chain, every expected runtime code hash, the Vault owner and current authority, executor evaluator, evaluator registry, and evaluator USD configuration. `VerifyDeployment` performs the same live read-only checks without broadcasting and rejects any nonzero Vault authority that is not the manifest executor, so an EOA or bypass contract cannot be recorded as an apparently valid deployment. When rotating authority, update the manifest only after the new executor is deployed, verified, and the authority transaction succeeds; until then, the old authority remains the expected value and a failed or misdirected configuration cannot be hidden by editing the record first. The executor does not configure authority and cannot execute against a different Vault than the one stored in the Mandate. If evaluation fails, the executor reverts before calling the Vault; if a later downstream action fails, the whole executor transaction reverts, so earlier actions are rolled back. `MandateRegistry` consumes each `(mandateId, agent, nonce)` once after evaluation and before external calls, and checks the Vault's current authority, so a successful plan cannot be replayed through a replacement executor while a failed plan's nonce consumption rolls back with the transaction. Different nonces remain independently executable and do not require strict ordering. The read-only evaluator does not consume nonces; the execution boundary requests consumption from the shared registry.

## Onchain records

Contracts emit events rather than storing large human-readable records. MandateRegistry events cover Mandate lifecycle, Vault events cover custody and low-level execution, and `VaultExecutor.ActionPlanExecuted` records the digest, Mandate, agent, Vault, nonce, aggregate native amount, quoted USD subtotal, whether any USD valuation was skipped, and action count after a complete plan succeeds. Denied plans and failed executions keep the current revert behavior, so their logs do not persist; evaluator results and revert data remain caller-visible until an offchain indexing and Decision Receipt layer is built.

## Deferred work

- [ ] Build a minimal offchain relayer after the contract execution loop is complete. It should accept a signed ActionPlan, submit `VaultExecutor.execute` with a funded EOA, and report the transaction receipt. It must remain a gas-paying caller only; `VaultExecutor` and the Vault authority configuration remain the enforcement boundary.
- [ ] Build offchain indexing and Decision Receipt assembly. It should combine signed ActionPlans, evaluator results, revert data, transaction receipts, Mandate events, Vault events, and `VaultExecutor` events into a queryable behavioural history without moving the enforcement boundary offchain.

## Current X Layer deployment

`deployments/xlayer-testnet.json` is the current deployment record. Run `forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url xlayer_testnet` after loading `.env` to confirm the live addresses, runtime hashes, owner, authority, dependency wiring, zero USD provider, enabled testnet skip mode, and registry state. The deployer key is intentionally not recorded.

## Contract decisions

| Date       | Decision                                                                                      | Reason and impact                                                                                                                                                |
| ---------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Use Foundry + Anvil.                                                                          | This keeps Solidity tests and local execution fast while supporting direct X Layer deployment and verification.                                                  |
| 2026-08-11 | Configure local and testnet networks, but do not configure mainnet deployment.                | The first proof must be safe and reproducible; mainnet access is unnecessary for the MVP environment setup.                                                      |
| 2026-08-11 | Keep the first smoke test free of Grantline logic.                                            | It proves the toolchain independently, so later contract failures are not confused with environment failures.                                                    |
| 2026-08-11 | Use a dependency-free `DeploymentProbe` before Grantline contracts.                           | It verifies signer, chain ID, broadcast, receipts, and remote reads without introducing product authority logic.                                                 |
| 2026-08-11 | Use one configurable Vault authority, initially unset.                                        | Owner custody remains available, while autonomous execution is impossible until a later authority contract is explicitly connected.                              |
| 2026-08-11 | Represent Agents as registered EOA addresses.                                                 | A Mandate can bind directly to the signing address without introducing smart accounts or a separate identity lifecycle.                                          |
| 2026-08-11 | Store Mandates in one sequential onchain registry.                                            | IDs, status, lifecycle history, and future indexing remain in one durable authority data layer.                                                                  |
| 2026-08-11 | Start with a single optional transaction limit.                                               | `transactionLimit == 0` means disabled, which lets a mandate omit the constraint while the enforcement path is designed separately.                              |
| 2026-08-11 | Represent agent proposals as ordered, atomic ActionPlans.                                     | Agents submit high-level typed intent; a later adapter can translate each action into validated Vault calls without exposing Solidity calldata.                  |
| 2026-08-11 | Version each Action payload independently.                                                    | `actionType + version` selects decoding rules, so future action types or changed transfer semantics do not reinterpret existing payloads.                        |
| 2026-08-11 | Use Grantline-managed proposal nonces and absolute Unix-second deadlines.                     | Nonces identify one execution slot without forcing strict ordering, while deadlines allow pending escalations to expire.                                         |
| 2026-08-11 | Store ActionPlan nonce consumption in MandateRegistry and gate it to current Vault authority. | The EVM transaction nonce belongs to the submitting wallet, and shared state prevents a signed plan from replaying after executor replacement.                   |
| 2026-08-11 | Sign ActionPlans with EIP-712.                                                                | Agents sign readable intent while the digest binds the complete ordered plan to chain ID and verifying contract, preventing cross-domain replay.                 |
| 2026-08-11 | Keep Mandate evaluation separate from decision aggregation.                                   | The evaluator returns the first structured failure so later Guardian and Preflight checks can compose before ALLOW, DENY, or ESCALATE is produced.               |
| 2026-08-11 | Keep `transactionLimit` as the native OKB cap and add USD as a separate limit.                | Native amounts remain directly enforceable in raw base units, while USD-valued exposure gets its own independently configurable constraint.                      |
| 2026-08-11 | Add an independent USD transaction limit for current transfers.                               | Native caps remain raw OKB limits, while a configured valuation provider can aggregate transfer value in USD; testnet may explicitly skip unavailable quotes.    |
| 2026-08-11 | Keep Vault custody unchanged and execute through a separate VaultExecutor.                    | Vault remains a simple authority-controlled custody primitive, while action translation and execution failure handling can evolve independently.                 |
| 2026-08-11 | Revert the complete executor transaction when a downstream action fails.                      | A plan is atomic, so partial capital movement cannot be mistaken for successful execution.                                                                       |
| 2026-08-11 | Enforce every available USD quote when some valuations are unavailable.                       | Skip mode marks incomplete valuation without discarding or bypassing the quoted subtotal, so authorisation no longer depends on action order.                    |
| 2026-08-11 | Validate chain and dependency identity before every authority broadcast.                      | Scripts fail before signing on a chain mismatch, and Vault authority changes require the expected owner, current authority, executor, evaluator, and registry.   |
| 2026-08-11 | Use a tracked deployment manifest as the operational trust source.                            | Addresses, runtime hashes, dependency wiring, and current authority stay together, so scripts do not trust independently editable address environment variables. |
| 2026-08-11 | Use `block.timestamp` for ActionPlan deadlines and accept the timestamp lint.                 | Onchain expiry needs the chain's standard Unix-second clock; deadlines are guardrails with caller-provided safety margins, not exact wall-clock timers.          |
| 2026-08-11 | Reject unsupported Action versions at both evaluation and execution.                          | The current transfer decoder supports version `1` only, so a future payload cannot be authorised and then silently decoded with old semantics.                   |

Update this file whenever contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
