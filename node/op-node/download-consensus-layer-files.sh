#!/usr/bin/env bash
set -euo pipefail

case "${NETWORK:-}" in
  ronin|saigon)
    ;;
  "")
    echo "NETWORK must be set"
    exit 1
    ;;
  *)
    echo "Unsupported NETWORK '${NETWORK}'. Expected one of: ronin, saigon"
    exit 1
    ;;
esac

rollup_config="/tmp/${NETWORK}-rollup.json"
rollup_url="https://storage.googleapis.com/conduit-public-dls/${NETWORK}-rollup.json"

if [ ! -f "$rollup_config" ]; then
  echo "Downloading ${rollup_url}"
  curl -fL --retry 5 --retry-delay 5 "$rollup_url" -o "$rollup_config"
fi

echo "Ensuring EigenDA alt_da config is present in rollup.json"
jq '.alt_da = {
  "da_commitment_type": "GenericCommitment",
  "da_challenge_contract_address": "0x0000000000000000000000000000000000000000",
  "da_challenge_window": 1,
  "da_resolve_window": 1
}' "$rollup_config" > "${rollup_config}.tmp"
mv "${rollup_config}.tmp" "$rollup_config"

OP_NODE_ROLLUP_CONFIG="$rollup_config" exec op-node "$@"
