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

The tracked `deployments/xlayer-testnet.json` retains the verified pre-feature X Layer testnet deployment identity for chain ID `1952`, not a record of the removed legacy stack. It contains the Grantline, coordinator, module proxies and implementations, runtime hashes, versions, Vault template authority, and explicit disabled native-asset and swap configuration; dynamic Vault snapshots are intentionally omitted. The deployment script reads the manifest and refuses to broadcast on a different chain. The recorded deployment and single-pass integration flow completed successfully before SWAP, nonce cancellation, and native-asset USD limits were added, so the current breaking code requires a fresh deployment rather than verification against those addresses.

## Commands

Run these from `contracts/`:

```sh
forge fmt --check
forge build
forge test
forge lint src script/DeployGrantline.s.sol script/VerifyGrantlineDeployment.s.sol test
```

`DeployGrantline` creates the Grantline proxy, internal module proxies, Vault implementation, and factory in one broadcast flow. Native-asset identity, the optional Chainlink USD feed and its decimals, and swap dependencies come from the manifest rather than environment variables. `VerifyGrantlineDeployment` checks the manifest-defined chain, proxy implementations, runtime hashes, initialisation, UUPS identifiers, ownership, authority, module wiring, native-asset configuration, live feed and wrapped-token metadata, factory state, and every live Vault enumerated from the factory. Manifests contain deployment identity and wiring only; they do not copy dynamic `vaultCount` or `vaults` state. The verifier also exposes `runWithManifest` for in-memory unit fixtures; production verification uses `DEPLOYMENT_MANIFEST_PATH`.

## Active architecture

The public surface is the Grantline UUPS proxy. Registry, evaluator, escalation manager, executor, and Vault factory are internal UUPS module proxies controlled by Grantline. Vaults are UUPS proxies created by the factory, owned by Grantline, assigned to a controller, and restricted to the configured executor for agent execution.

Grantline exposes controller-scoped Vault enumeration through `controllerVaultCount` and `controllerVaultAt`, while MandateRegistry keeps append-only indexes by Vault, creator, and assigned agent. EscalationManager keeps append-only digest indexes globally, by Vault, and by agent; `submittedBy` remains part of each historical Escalation record without becoming an enumeration key. These reads are discoverability helpers only, so existing controller and execution authorisation checks remain authoritative.

`Grantline` preserves actor context while exposing Vault creation and funding, Mandate lifecycle, typed Action Plan evaluation and execution, escalation approval or denial, views, and controller-authorised Vault and Mandate pause controls. Repeated Mandate, delegation, and nonce-cancellation authorisation is enforced by MandateRegistry at the module boundary, while Grantline retains custody, Vault-pause, escalation-controller, event, upgrade, and reentrancy responsibilities. `GrantlineAdmin` is a separate non-upgradeable protocol coordinator with no independent owner; its protocol-admin checks derive from `Grantline.owner()`, while every module and Vault upgrade check reads the current `Grantline.adminController()` pointer. It validates adapter inputs and wiring, manages module and Vault upgrades, validates initialized Vault template state including the Vault's Grantline binding, checks the same binding after existing-Vault upgrades, changes the future Vault template, and reassigns Vault controllers. Replacing the coordinator updates one Grantline pointer, so old coordinators lose module and Vault upgrade authority without a module-ownership migration. Direct calls to internal modules, direct protocol-admin calls to the user facade's removed admin operations, and direct agent calls to Vault authority functions fail.

The active source tree defines each protocol type once in `GrantlineTypes.sol` and `ActionTypes.sol`. `ActionSignature.sol` supplies the custom nested Action Plan hashing used with the Grantline EIP-712 domain. OpenZeppelin `SafeERC20`, `ECDSA`, `ERC1967Proxy`, UUPS identifiers, the upgradeable `Initializable`, `UUPSUpgradeable`, `Ownable2StepUpgradeable`, and `EIP712Upgradeable` contracts, plus standard `ReentrancyGuard`, cover token, signature, proxy, implementation, initialisation, ownership, domain, and reentrancy behaviour. Grantline-specific authority, delegation, policy, escalation, and execution rules remain custom.

Every Grantline component exposes a role-specific `componentType()` identifier. The admin coordinator validates module roles, the current Grantline binding, both registry links used by the evaluator, escalation manager, and executor, and Vault identity, owner, pending ownership, executor authority, pause state, and pause-interface version after upgrades. Vault template selection and existing Vault upgrades share the factory's full UUPS, role, version, pause-interface, and callable pause-entrypoint validation. Deployment verification and the integration preflight enforce the same invariants, so a UUPS-compatible contract for the wrong role, a module bound to another Grantline, an inconsistent registry link, or an incomplete Vault interface cannot produce a superficially valid stack.

The protocol preserves effective ancestor authority, narrower delegation, current-state re-evaluation, native amount bounds, native-balance and native-USD reserve Preflight, `ALLOW`/`ESCALATE`/`DENY` outcomes, complete-plan escalation reservations, nonce-aware evaluator results, nonce replay protection, targeted cancellation of unused and unreserved nonces, atomic typed execution, and shared reentrancy protection across normal and escalated entrypoints. The exact Mandate agent or current Vault controller can cancel through Grantline even while authority is paused, outside its validity window, or revoked; parent agents cannot cancel child nonces, and the Registry repeats the authority check before consuming the nonce. Optional native-asset USD rules use one manifest-defined Chainlink feed, treat rule values as whole dollars, aggregate native and canonical wrapped-native action inputs for plan valuation, value only actual native balance for USD Preflight reserves, intersect across lineage, and fail closed when a required current answer is unavailable or invalid. Feed staleness is intentionally not enforced yet, arbitrary ERC-20 inputs are not valued, and deployments with no configured feed reject nonzero native-USD rules. Protocol-admin operations deliberately live on `GrantlineAdmin`: `setVaultImplementation` changes only future Vault proxies, `upgradeVault` changes one existing Vault, `upgradeModules` changes internal module proxies, and `setVaultController` changes one Vault's controller assignment. Grantline remains the Vault owner for custody and pause controls, while module and Vault UUPS checks follow the current admin-controller pointer.

Vault controllers can pause and unpause their Vaults through Grantline. A Vault pause blocks autonomous execution, escalation submission and approval, and new Mandate creation while preserving controller deposits, withdrawals, Mandate administration, and recovery. Mandates support an appended `PAUSED` status with inherited ancestor pauses; paused escalations remain stored and are re-evaluated after unpause.

## Current status and audit

The current local run has 185 passing tests after adding scoped Vault, Mandate, and Escalation read coverage; the older historical counts below describe earlier checkpoints.

The current implementation supersedes the earlier ownership-handover design: `Grantline.setAdminController` now validates the replacement's Grantline binding and updates one live authority pointer, while modules and Vaults read that pointer for UUPS upgrades. There is no module ownership transfer, acceptance callback, factory upgrade-authority field, or Vault upgrade-authority migration. The local suite has 185 passing tests, including the scoped-record index coverage; a fresh deployment is required because the new indexes and `createdBy` storage are not present in the tracked X Layer deployment.

The current breaking architecture gives `Grantline.setAdminController` a validated live-pointer handover: the replacement must identify the same Grantline, then modules and Vaults read the new pointer for upgrade authority, so no ownership or Vault batch migration is required. The local suite now has 177 passing tests.

The local suite contains 179 passing tests across the facade, evaluator boundaries, delegation narrowing, custody and cross-Vault isolation, execution atomicity and reentrancy, token return conventions, escalation reservations and transitions, targeted nonce cancellation, admin separation and proxy upgrades, synchronized protocol-admin ownership, component-role and ownership checks, initialized Vault-template validation, pause controls and lineage semantics, mandate validity windows, native-asset USD valuation and USD Preflight reserve valuation, rounding and arithmetic overflow, SWAP route validation and execution, incomplete Vault-interface rejection, deployment verification, and fuzzed nonce, deadline, limit, and digest properties. `TestnetIntegration.s.sol` covers the fresh-manifest guard, controller and module isolation, native and token execution, targeted cancellation, atomic rollback, reentrancy, escalation reservation and approval, nested delegation, inherited Preflight, revocation, admin-coordinated upgrades, cleanup, and final manifest verification; its manifest reconstruction now preserves native-asset and adapter configuration, but no new network run was performed. The latest source-focused coverage is 85.98% lines, 85.92% statements, 54.93% branches, and 99.57% functions across `contracts/src`. Solhint passes with only its offline update-check warning; Slither 0.11.6 reports the remaining intentional forwarded-transfer, strict-equality, bounded external-loop, benign reentrancy, adapter accounting, timestamp, optional zero-configuration, and ignored Chainlink round-metadata findings. SWAP v1, targeted nonce cancellation, native-asset USD limits, and USD Preflight reserve floors are local-only until a fresh manifest-configured deployment and later integration pass are approved; the current X Layer stack remains unchanged and exposes none of those capabilities.

The code audit checked for duplicate protocol definitions, stale imports, direct bypass entrypoints, proxy initialisation and upgrade checks, Vault/controller isolation, authority wiring, upgrade metadata rollback, manifest verification, integration rejection paths, and test-suite leakage. No duplicate `MandateStatus`, `MandateRules`, or `PreflightRules` definitions remain, and no legacy source is referenced by the active build.

## Deferred work

- Repeat the single-pass integration flow against a fresh local deployment when local end-to-end evidence is needed; the X Layer testnet evidence is recorded in `deployments/xlayer-testnet.json`.
- Deploy and integrate SWAP v1 only through a fresh manifest that explicitly enables a supported adapter; do not retrofit the current X Layer stack or use a production mock.
- Add sponsored submission, indexing and receipt assembly, Guardian enforcement, generic token USD valuation, Chainlink staleness enforcement, protocol-wide pause controls, and stronger protocol-admin governance as separate follow-up work.

Update this file when contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
