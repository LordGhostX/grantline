# Contracts Working Memory

## Purpose and boundary

This directory owns Grantline's Solidity contracts, Foundry tests, deployment scripts, and contract-local development configuration. It is the enforcement boundary for Vault custody, Mandates, Actions, authorisation decisions, execution, delegation, revocation, and onchain Records as those features are implemented.

## Layout

```text
contracts/
├── AGENTS.md
├── .env.example             # Safe configuration template; no secrets
├── foundry.toml             # Foundry profiles and RPC aliases
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

The expected Anvil chain ID is `31337`. The expected X Layer testnet chain ID is `1952`; a mismatch is a configuration failure and must be investigated before deployment.

## Current status and handoff

The workspace contains the Foundry toolchain smoke test, the `DeploymentProbe`, the `Vault`, and the `MandateRegistry`. `forge test` passes with Foundry 1.7.1, Anvil responds on chain ID `31337`, and the X Layer RPC responds on chain ID `1952`.

The Vault and MandateRegistry deployment paths are verified on local Anvil and X Layer testnet. Both deployed Vaults start with authority unset, and the MandateRegistry starts empty, so no autonomous execution or authority evaluation is enabled. Mandates currently store an optional per-transaction limit; `transactionLimit == 0` means disabled. The limit is data only for now and is not enforced by the Vault itself. The recorded X Layer MandateRegistry deployment predates this transaction-only schema change and has not been redeployed. `ActionTypes` now defines an atomic, ordered ActionPlan with versioned high-level action payloads; only `TRANSFER` is currently defined, and raw Vault calldata is intentionally outside the agent-facing format. `ActionSignature` provides EIP-712 hashing and low-s malleability-checked signer recovery, and `MandateEvaluator` now performs read-only Mandate, signature, deadline, action-shape, and native-amount checks. `VaultExecutor` now translates evaluator-approved native and ERC-20 transfers into atomic Vault calls. Nonce consumption, action-hash storage, adapters beyond transfers, decision aggregation, records, and relaying remain unimplemented.

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

`actions` is an ordered, atomic plan. `nonce` is a Grantline-managed proposal identifier scoped to the mandate and agent; it does not force strict execution order. `deadline` is an absolute Unix timestamp in seconds, with `0` meaning no expiry. The `type` and `version` select the typed decoder, and `ActionTypes` currently supports only `transfer`; nonzero versions use the existing transfer payload shape until version-specific decoding is added. `native` maps to the zero address internally; token amounts use raw base units. Typed parameters are translated into validated Vault calls, while raw calldata remains outside the agent-facing format.

## Agent signatures

`ActionSignature` uses EIP-712 with domain name `Grantline`, domain version `1`, the active chain ID, and the verifying-contract address. The signed digest covers the complete ActionPlan, including the ordered action array and each action's exact typed parameter bytes. A valid signature must recover to `ActionPlan.agent`; malformed, non-27/28, or high-`s` signatures return an invalid signer. The verifying contract is supplied by the eventual authority/execution boundary, so signatures are not portable across chains or contracts.

## Mandate evaluation

`MandateEvaluator` returns a structured pass/fail result and stops at the first failure; it does not emit ALLOW or DENY. It checks Mandate existence and activity, agent binding, EIP-712 signature, deadline, non-empty actions, nonzero action version and parameters, and the transfer payload's recipient and amount. A nonzero `transactionLimit` is currently interpreted as native OKB base units and applies to the aggregate native amount across the plan. Token amounts are not compared or rejected because no asset guard or valuation source exists yet; only native amounts contribute to the limit. A disabled limit (`transactionLimit == 0`) skips amount enforcement. Future Guardian, Preflight, and decision checks should consume this result rather than be folded into the evaluator.

## Vault execution

`VaultExecutor` is the execution boundary above the low-level `Vault`. It re-runs `MandateEvaluator`, confirms the Mandate points to the supplied Vault, and translates each supported `TRANSFER` action into a `Vault.execute` call. Native transfers target the recipient directly; token transfers call ERC-20 `transfer` through the Vault. The executor accepts the standard empty or `true` ERC-20 return conventions and rejects false, malformed, or missing token targets.

The Vault owner must explicitly set the executor as the Vault authority. The executor does not configure authority and cannot execute against a different Vault than the one stored in the Mandate. If evaluation fails, the executor reverts before calling the Vault; if a later downstream action fails, the whole executor transaction reverts, so earlier actions are rolled back. The signed nonce is currently not consumed, so replay protection remains unfinished.

## Deployment evidence

| Deployment                                 | Chain ID | Contract address                             | Transaction hash                                                     |
| ------------------------------------------ | -------: | -------------------------------------------- | -------------------------------------------------------------------- |
| DeploymentProbe · local Anvil (fresh node) |  `31337` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | Stored in the ignored local broadcast receipt                        |
| DeploymentProbe · X Layer testnet          |   `1952` | `0xdeFC33e462C77AbbA7DCaEa2888FA5B937e9eC91` | `0xccf3c6f6b9d081e549f0ad5156cad85cc5e9476a2e7e4fb6176f3da779ea33d9` |
| Vault · local Anvil (fresh node)           |  `31337` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | Stored in the ignored local broadcast receipt                        |
| Vault · X Layer testnet                    |   `1952` | `0xee1C3897A9c69460a3957d17B7B368B4162F6129` | `0x18cfe66cb3003486738f2624a1ca209af51103d4d966c16d8710d7502df5bcee` |
| MandateRegistry · local Anvil (fresh node) |  `31337` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | Stored in the ignored local broadcast receipt                        |
| MandateRegistry · X Layer testnet          |   `1952` | `0x5c6c7b9850385190D297B55C1C81f99adb0fd1d7` | `0x9bfc665985d4ce11cb71ae3769b7404d3ac9dc4155a89bafd0cbc4e7cdf6f7da` |

The probe returns the configured deployer and chain ID `1952` on X Layer, and exposes version `grantline-deployment-probe-v1`. The deployer key is intentionally not recorded.

## Contract decisions

| Date       | Decision                                                                       | Reason and impact                                                                                                                                  |
| ---------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Use Foundry + Anvil.                                                           | This keeps Solidity tests and local execution fast while supporting direct X Layer deployment and verification.                                    |
| 2026-08-11 | Configure local and testnet networks, but do not configure mainnet deployment. | The first proof must be safe and reproducible; mainnet access is unnecessary for the MVP environment setup.                                        |
| 2026-08-11 | Keep the first smoke test free of Grantline logic.                             | It proves the toolchain independently, so later contract failures are not confused with environment failures.                                      |
| 2026-08-11 | Use a dependency-free `DeploymentProbe` before Grantline contracts.            | It verifies signer, chain ID, broadcast, receipts, and remote reads without introducing product authority logic.                                   |
| 2026-08-11 | Use one configurable Vault authority, initially unset.                         | Owner custody remains available, while autonomous execution is impossible until a later authority contract is explicitly connected.                |
| 2026-08-11 | Represent Agents as registered EOA addresses.                                  | A Mandate can bind directly to the signing address without introducing smart accounts or a separate identity lifecycle.                            |
| 2026-08-11 | Store Mandates in one sequential onchain registry.                             | IDs, status, lifecycle history, and future indexing remain in one durable authority data layer.                                                    |
| 2026-08-11 | Start with a single optional transaction limit.                                | `transactionLimit == 0` means disabled, which lets a mandate omit the constraint while the enforcement path is designed separately.                |
| 2026-08-11 | Represent agent proposals as ordered, atomic ActionPlans.                      | Agents submit high-level typed intent; a later adapter can translate each action into validated Vault calls without exposing Solidity calldata.    |
| 2026-08-11 | Version each Action payload independently.                                     | `actionType + version` selects decoding rules, so future action types or changed transfer semantics do not reinterpret existing payloads.          |
| 2026-08-11 | Use Grantline-managed proposal nonces and absolute Unix-second deadlines.      | Nonces can bind retries to one action hash without forcing strict execution order, while deadlines allow pending escalations to expire.            |
| 2026-08-11 | Sign ActionPlans with EIP-712.                                                 | Agents sign readable intent while the digest binds the complete ordered plan to chain ID and verifying contract, preventing cross-domain replay.   |
| 2026-08-11 | Keep Mandate evaluation separate from decision aggregation.                    | The evaluator returns the first structured failure so later Guardian and Preflight checks can compose before ALLOW, DENY, or ESCALATE is produced. |
| 2026-08-11 | Treat the MVP transaction limit as native OKB only.                            | Raw amounts from different tokens cannot share a global numeric limit; token amounts are skipped until a valuation or asset-specific guard exists. |
| 2026-08-11 | Keep Vault custody unchanged and execute through a separate VaultExecutor.     | Vault remains a simple authority-controlled custody primitive, while action translation and execution failure handling can evolve independently.   |
| 2026-08-11 | Revert the complete executor transaction when a downstream action fails.       | A plan is atomic, so partial capital movement cannot be mistaken for successful execution.                                                         |

Update this file whenever contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
