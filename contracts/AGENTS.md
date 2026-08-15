# Contracts Working Memory

## Purpose and boundary

This directory owns Grantline's Solidity contracts, Foundry tests, deployment scripts, and contract-local configuration. It is the enforcement boundary for Vault custody, Mandates, typed Action Plans, authorisation decisions, escalation, execution, delegation, revocation, and onchain records.

## Layout

```text
contracts/
├── AGENTS.md
├── .env.example
├── foundry.toml
├── deployments/              # Tracked deployment manifests and runtime hashes
├── src/                      # The single active Grantline source tree
├── test/                     # Grantline architecture tests and toolchain smoke test
├── script/                   # Grantline deployment and verification scripts
└── lib/                      # Pinned Foundry dependencies
```

The old root contract stack, duplicate protocol types, old deployment scripts, old tests, and old integration script were removed for the breaking refactor. The replacement single-pass integration flow is `script/TestnetIntegration.s.sol`; it is intentionally separate from the unit-test suite and requires a fresh full manifest.

## Environment

The first remote target is X Layer testnet:

- Network: X Layer testnet
- Chain ID: `1952`
- Gas token: `OKB`
- Primary RPC: `https://testrpc.xlayer.tech/terigon`
- Explorer: `https://web3.okx.com/explorer/x-layer-testnet`

Copy `.env.example` to `.env`. Keep private keys only in the untracked `.env` or in the command environment. `DeployGrantline` uses the deployer key, while `TestnetIntegration` uses the deployer, agent, and delegated-agent variables for separate signing and submission identities.

The tracked `deployments/xlayer-testnet.json` currently contains only the target network and chain ID. It is a bootstrap manifest for the fresh Grantline deployment, not a record of the removed legacy stack. The deployment script reads the manifest and refuses to broadcast on a different chain. After deployment, the operator must record the proxy addresses, implementation addresses, runtime hashes, versions, authority, controller assignments, and Vault records in the same manifest before verification.

## Commands

Run these from `contracts/`:

```sh
forge fmt --check
forge build
forge test
forge lint src script/DeployGrantline.s.sol script/VerifyGrantlineDeployment.s.sol test
```

`DeployGrantline` creates the Grantline proxy, internal module proxies, Vault implementation, and factory in one broadcast flow. `VerifyGrantlineDeployment` checks the manifest-defined chain, proxy implementations, runtime hashes, initialisation, UUPS identifiers, ownership, authority, module wiring, factory state, and every recorded Vault. It also exposes `runWithManifest` for in-memory unit fixtures; production verification uses `DEPLOYMENT_MANIFEST_PATH`.

## Active architecture

The public surface is the Grantline UUPS proxy. Registry, evaluator, escalation manager, executor, and Vault factory are internal UUPS module proxies controlled by Grantline. Vaults are UUPS proxies created by the factory, owned by Grantline, assigned to a controller, and restricted to the configured executor for agent execution.

`Grantline` preserves actor context while exposing Vault creation and funding, Mandate lifecycle, typed Action Plan evaluation and execution, escalation approval or denial, views, and explicit protocol-admin upgrade operations. Direct calls to internal modules and direct agent calls to Vault authority functions fail.

The active source tree defines each protocol type once in `GrantlineTypes.sol` and `ActionTypes.sol`. `ActionSignature.sol` supplies the custom nested Action Plan hashing used with the Grantline EIP-712 domain. OpenZeppelin `SafeERC20`, `ECDSA`, `ERC1967Proxy`, and UUPS identifiers cover standard token, signature, proxy, and implementation checks; the repository currently supplies its own upgrade-safe initialisation, ownership, and reentrancy primitives because the installed dependency does not include the upgradeable package.

The protocol preserves effective ancestor authority, narrower delegation, current-state re-evaluation, native-balance Preflight, `ALLOW`/`ESCALATE`/`DENY` outcomes, complete-plan escalation reservations, nonce replay protection, atomic typed execution, and shared reentrancy protection across normal and escalated entrypoints. Protocol-admin operations deliberately remain separate: `setVaultImplementation` changes only future Vault proxies, `upgradeVault` changes one existing Vault, and `setVaultController` changes one Vault's controller assignment.

## Current status and audit

The Grantline-only local suite contains 58 passing tests across the facade, evaluator boundaries, delegation narrowing, custody and cross-Vault isolation, execution atomicity and reentrancy, token return conventions, escalation reservations and transitions, proxy upgrades, deployment verification, and fuzzed nonce, deadline, limit, and digest properties. `TestnetIntegration.s.sol` covers the fresh-manifest guard, controller and module isolation, native and token execution, atomic rollback, reentrancy, escalation reservation and approval, nested delegation, inherited Preflight, revocation, upgrades, cleanup, and final manifest verification; its end-to-end deployment run remains deferred. `forge coverage --ir-minimum` is currently blocked before execution by a minimum-IR compiler stack-depth error in `TestnetIntegration.s.sol`; the normal build, full test suite, formatter check, and lint pass. The latest lint emits only the intentional `block.timestamp` warning for Action Plan deadlines.

The code audit checked for duplicate protocol definitions, stale imports, direct bypass entrypoints, proxy initialisation and upgrade checks, Vault/controller isolation, authority wiring, upgrade metadata rollback, manifest verification, integration rejection paths, and test-suite leakage. No duplicate `MandateStatus`, `MandateRules`, or `PreflightRules` definitions remain, and no legacy source is referenced by the active build.

## Deferred work

- Run the single-pass integration flow against fresh local and X Layer deployments using the reserved deployer, agent, and delegated-agent configuration, then record the evidence.
- Replace the bootstrap manifest with the verified Grantline deployment record only after deployment and integration evidence exist.
- Add sponsored submission, indexing and receipt assembly, Guardian enforcement, production USD valuation, pause controls, and stronger protocol-admin governance as separate follow-up work.

Update this file when contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
