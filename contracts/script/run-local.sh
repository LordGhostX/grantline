#!/usr/bin/env bash
set -euo pipefail

rpc_url="${LOCAL_ANVIL_RPC_URL:-http://127.0.0.1:8545}"
manifest_path="cache/anvil-local.json"

required_vars=(
  DEPLOYER_PRIVATE_KEY
  AGENT_PRIVATE_KEY
  DELEGATED_AGENT_PRIVATE_KEY
  AGENT_PUBLIC_KEY
  DELEGATED_AGENT_PUBLIC_KEY
)

for variable_name in "${required_vars[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'missing required environment variable: %s\n' "$variable_name" >&2
    exit 1
  fi
done

mkdir -p cache
cp deployments/anvil-bootstrap.json "$manifest_path"

DEPLOYMENT_MANIFEST_PATH="$manifest_path" forge script script/DeployGrantline.s.sol:DeployGrantline \
  --rpc-url "$rpc_url" --broadcast

DEPLOYMENT_MANIFEST_PATH="$manifest_path" forge script script/VerifyGrantlineDeployment.s.sol:VerifyGrantlineDeployment \
  --rpc-url "$rpc_url"

DEPLOYMENT_MANIFEST_PATH="$manifest_path" forge script script/TestnetIntegration.s.sol:TestnetIntegration \
  --rpc-url "$rpc_url" --broadcast
