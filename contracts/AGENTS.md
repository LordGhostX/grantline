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

The workspace contains the Foundry toolchain smoke test and the `DeploymentProbe`. `forge test` passes with Foundry 1.7.1, Anvil responds on chain ID `31337`, and the X Layer RPC responds on chain ID `1952`. No Grantline product contract has been deployed.

The deployment path is now verified on local Anvil and X Layer testnet. Next: build the Vault while preserving the same deployment and receipt workflow.

## Deployment evidence

| Network | Chain ID | Contract address | Transaction hash | Explorer |
| --- | ---: | --- | --- | --- |
| Local Anvil | `31337` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | Stored in the ignored local broadcast receipt | Local node only |
| X Layer testnet | `1952` | `0xdeFC33e462C77AbbA7DCaEa2888FA5B937e9eC91` | `0xccf3c6f6b9d081e549f0ad5156cad85cc5e9476a2e7e4fb6176f3da779ea33d9` | [X Layer testnet explorer](https://web3.okx.com/explorer/x-layer-testnet) |

The probe returns the configured deployer and chain ID `1952` on X Layer, and exposes version `grantline-deployment-probe-v1`. The deployer key is intentionally not recorded.

## Contract decisions

| Date       | Decision                                                                       | Reason and impact                                                                                               |
| ---------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Use Foundry + Anvil.                                                           | This keeps Solidity tests and local execution fast while supporting direct X Layer deployment and verification. |
| 2026-08-11 | Configure local and testnet networks, but do not configure mainnet deployment. | The first proof must be safe and reproducible; mainnet access is unnecessary for the MVP environment setup.     |
| 2026-08-11 | Keep the first smoke test free of Grantline logic.                             | It proves the toolchain independently, so later contract failures are not confused with environment failures.   |
| 2026-08-11 | Use a dependency-free `DeploymentProbe` before Grantline contracts.             | It verifies signer, chain ID, broadcast, receipts, and remote reads without introducing product authority logic. |

Update this file whenever contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
