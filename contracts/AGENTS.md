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
- Explorer: `https://www.okx.com/web3/explorer/xlayer-test`

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

The workspace currently contains only the Foundry toolchain smoke test. `forge test` passes with Foundry 1.7.1, Anvil responds on chain ID `31337`, and the X Layer RPC responds on chain ID `1952`. No Grantline contract has been deployed, and no deployer key is required for the read-only RPC checks.

Next: deploy a basic test contract to local Anvil and X Layer testnet, record its addresses and explorer links, and keep deployment scripts and receipts inside this directory.

## Contract decisions

| Date       | Decision                                                                       | Reason and impact                                                                                               |
| ---------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| 2026-08-11 | Use Foundry + Anvil.                                                           | This keeps Solidity tests and local execution fast while supporting direct X Layer deployment and verification. |
| 2026-08-11 | Configure local and testnet networks, but do not configure mainnet deployment. | The first proof must be safe and reproducible; mainnet access is unnecessary for the MVP environment setup.     |
| 2026-08-11 | Keep the first smoke test free of Grantline logic.                             | It proves the toolchain independently, so later contract failures are not confused with environment failures.   |

Update this file whenever contract boundaries, deployment flow, network configuration, or security assumptions change. Do not record secrets or transient command output here.
