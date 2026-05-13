#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_SERVICE=""
LOCAL_RPC=""
PUBLIC_RPC=""
OP_NODE_RPC=""
EXPECTED_CHAIN_ID=""
BLOCK_LAG_THRESHOLD=5

usage() {
  cat <<'USAGE'
Usage: scripts/check_sync.sh [options]

Options:
  --env-file PATH          Env file to use (default: .env)
  --compose-service NAME   Run curl from this Compose service
  --local-rpc URL          Local execution RPC URL
  --public-rpc URL         Reference RPC URL
  --op-node-rpc URL        Local op-node RPC URL for OP Stack sync status
  --expected-chain-id ID   Expected chain ID, hex or decimal
  --block-lag N            Acceptable lag in blocks (default: 5)
  -h, --help               Show this help

Exit codes:
  0 synced
  1 syncing
  2 diverged or wrong chain
  3 local RPC error
  4 public RPC error
  5 configuration error
  6 missing dependency
USAGE
}

env_get() {
  local key="$1"
  local default="${2:-}"
  local source_file="$ENV_FILE"

  if [ ! -f "$source_file" ]; then
    source_file=default.env
  fi

  awk -F= -v key="$key" -v default="$default" '
    $0 ~ "^[[:space:]]*#" || $0 ~ "^[[:space:]]*$" { next }
    $1 == key {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      found=1
      exit
    }
    END {
      if (!found) {
        print default
      }
    }
  ' "$source_file"
}

to_dec() {
  local value="$1"

  if [[ "$value" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    value="${value#0x}"
    value="${value#0X}"
    echo $((16#$value))
  elif [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo ""
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --compose-service)
      COMPOSE_SERVICE="$2"
      shift 2
      ;;
    --local-rpc)
      LOCAL_RPC="$2"
      shift 2
      ;;
    --public-rpc)
      PUBLIC_RPC="$2"
      shift 2
      ;;
    --op-node-rpc)
      OP_NODE_RPC="$2"
      shift 2
      ;;
    --expected-chain-id)
      EXPECTED_CHAIN_ID="$2"
      shift 2
      ;;
    --block-lag)
      BLOCK_LAG_THRESHOLD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 5
      ;;
  esac
done

if [ -z "$LOCAL_RPC" ]; then
  LOCAL_RPC="http://127.0.0.1:$(env_get RPC_PORT 8545)"
fi

if [ -z "$PUBLIC_RPC" ]; then
  PUBLIC_RPC="$(env_get RETH_SEQUENCER_URL)"
fi

if [ -z "$EXPECTED_CHAIN_ID" ]; then
  EXPECTED_CHAIN_ID="$(env_get EXPECTED_CHAIN_ID)"
fi

if [ -z "$OP_NODE_RPC" ]; then
  op_node_port="$(env_get OP_NODE_RPC_PORT 7545)"
  OP_NODE_RPC="http://127.0.0.1:${op_node_port}"
fi

if [ -z "$PUBLIC_RPC" ]; then
  echo "Missing public RPC. Set RETH_SEQUENCER_URL or pass --public-rpc." >&2
  exit 5
fi

project_name="$(env_get PROJECT_NAME ronin)"

http_post() {
  local url="$1"
  local payload="$2"

  if [ -n "$COMPOSE_SERVICE" ]; then
    docker compose --env-file "$ENV_FILE" --project-name "$project_name" exec -T "$COMPOSE_SERVICE" \
      curl -fsS -H "content-type: application/json" --data "$payload" "$url"
  else
    curl -fsS -H "content-type: application/json" --data "$payload" "$url"
  fi
}

jq_eval() {
  local expr="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r "$expr"
  elif [ -n "$COMPOSE_SERVICE" ]; then
    docker compose --env-file "$ENV_FILE" --project-name "$project_name" exec -T "$COMPOSE_SERVICE" jq -r "$expr"
  else
    echo "jq is required when --compose-service is not used" >&2
    exit 6
  fi
}

rpc_payload() {
  local method="$1"
  local params="${2:-[]}"
  printf '{"jsonrpc":"2.0","id":1,"method":"%s","params":%s}' "$method" "$params"
}

chain_json="$(http_post "$LOCAL_RPC" "$(rpc_payload eth_chainId)")" || {
  echo "Local RPC did not answer eth_chainId: ${LOCAL_RPC}" >&2
  exit 3
}
chain_id="$(printf '%s' "$chain_json" | jq_eval '.result // empty')"
chain_id_dec="$(to_dec "$chain_id")"

if [ -n "$EXPECTED_CHAIN_ID" ]; then
  expected_chain_id_dec="$(to_dec "$EXPECTED_CHAIN_ID")"
  if [ -z "$chain_id_dec" ] || [ "$chain_id_dec" != "$expected_chain_id_dec" ]; then
    echo "Wrong chain ID: got ${chain_id:-empty}, expected ${EXPECTED_CHAIN_ID}" >&2
    exit 2
  fi
fi

local_sync_json="$(http_post "$LOCAL_RPC" "$(rpc_payload eth_syncing)")" || {
  echo "Local RPC did not answer eth_syncing: ${LOCAL_RPC}" >&2
  exit 3
}
local_sync="$(printf '%s' "$local_sync_json" | jq_eval '.result')"

if [ "$local_sync" != "false" ] && [ "$local_sync" != "null" ]; then
  current_hex="$(printf '%s' "$local_sync" | jq_eval '.currentBlock // empty')"
  highest_hex="$(printf '%s' "$local_sync" | jq_eval '.highestBlock // empty')"
  if [ -n "$current_hex" ] && [ -n "$highest_hex" ]; then
    current="$(to_dec "$current_hex")"
    highest="$(to_dec "$highest_hex")"
    sync_gap=$((highest - current))
    if [ "$sync_gap" -gt "$BLOCK_LAG_THRESHOLD" ]; then
      echo "Node reports syncing: ${current} / ${highest}"
      exit 1
    fi
    echo "Node reports syncing at target height: ${current} / ${highest}"
    echo "Continuing with public RPC validation"
  else
    echo "Node reports syncing"
    exit 1
  fi
fi

local_block_json="$(http_post "$LOCAL_RPC" "$(rpc_payload eth_blockNumber)")" || {
  echo "Local RPC did not answer eth_blockNumber: ${LOCAL_RPC}" >&2
  exit 3
}
public_block_json="$(http_post "$PUBLIC_RPC" "$(rpc_payload eth_blockNumber)")" || {
  echo "Public RPC did not answer eth_blockNumber: ${PUBLIC_RPC}" >&2
  exit 4
}

local_hex="$(printf '%s' "$local_block_json" | jq_eval '.result // empty')"
public_hex="$(printf '%s' "$public_block_json" | jq_eval '.result // empty')"

if [ -z "$local_hex" ]; then
  echo "Local RPC returned no block number" >&2
  exit 3
fi

if [ -z "$public_hex" ]; then
  echo "Public RPC returned no block number" >&2
  exit 4
fi

local_block="$(to_dec "$local_hex")"
public_block="$(to_dec "$public_hex")"
lag=$((public_block - local_block))

echo "Chain ID:     ${chain_id_dec:-unknown}"
echo "Local block:  ${local_block}"
echo "Public block: ${public_block}"
echo "Lag:          ${lag} blocks"

if [ "$public_block" -ge "$local_block" ]; then
  block_params="[\"${local_hex}\",false]"
  local_hash_json="$(http_post "$LOCAL_RPC" "$(rpc_payload eth_getBlockByNumber "$block_params")")" || {
    echo "Local RPC did not answer eth_getBlockByNumber: ${LOCAL_RPC}" >&2
    exit 3
  }
  public_hash_json="$(http_post "$PUBLIC_RPC" "$(rpc_payload eth_getBlockByNumber "$block_params")")" || {
    echo "Public RPC did not answer eth_getBlockByNumber: ${PUBLIC_RPC}" >&2
    exit 4
  }
  local_hash="$(printf '%s' "$local_hash_json" | jq_eval '.result.hash // empty')"
  public_hash="$(printf '%s' "$public_hash_json" | jq_eval '.result.hash // empty')"

  if [ -n "$local_hash" ] && [ -n "$public_hash" ] && [ "$local_hash" != "$public_hash" ]; then
    echo "Block hash mismatch at ${local_block}" >&2
    echo "Local:  ${local_hash}" >&2
    echo "Public: ${public_hash}" >&2
    exit 2
  fi
fi

op_sync_json=""
if [ -n "$OP_NODE_RPC" ]; then
  op_sync_json="$(http_post "$OP_NODE_RPC" "$(rpc_payload optimism_syncStatus)" 2>/dev/null || true)"
fi

if [ -n "$op_sync_json" ]; then
  unsafe_l2="$(printf '%s' "$op_sync_json" | jq_eval '.result.unsafe_l2.number // empty')"
  safe_l2="$(printf '%s' "$op_sync_json" | jq_eval '.result.safe_l2.number // empty')"
  finalized_l2="$(printf '%s' "$op_sync_json" | jq_eval '.result.finalized_l2.number // empty')"
  current_l1="$(printf '%s' "$op_sync_json" | jq_eval '.result.current_l1.number // empty')"
  head_l1="$(printf '%s' "$op_sync_json" | jq_eval '.result.head_l1.number // empty')"
  unsafe_l2_dec="$(to_dec "$unsafe_l2")"

  echo "Unsafe L2:    ${unsafe_l2:-unknown}"
  echo "Safe L2:      ${safe_l2:-unknown}"
  echo "Finalized L2: ${finalized_l2:-unknown}"
  echo "L1 origin:    ${current_l1:-unknown} / ${head_l1:-unknown}"

  if [ -n "$unsafe_l2_dec" ] && [ "$unsafe_l2_dec" -lt $((public_block - BLOCK_LAG_THRESHOLD)) ]; then
    lag=$((public_block - unsafe_l2_dec))
  fi

  peer_json="$(http_post "$OP_NODE_RPC" "$(rpc_payload opp2p_peerStats)" 2>/dev/null || true)"
  if [ -n "$peer_json" ]; then
    connected_peers="$(printf '%s' "$peer_json" | jq_eval '.result.connected // empty')"
    echo "OP peers:     ${connected_peers:-unknown}"
    if [ "${connected_peers:-0}" = "0" ]; then
      echo "Node is syncing: op-node has no connected peers"
      exit 1
    fi
  fi
fi

if [ "$lag" -le "$BLOCK_LAG_THRESHOLD" ] && [ "$lag" -ge "-$BLOCK_LAG_THRESHOLD" ]; then
  echo "Node is synced"
  exit 0
fi

if [ "$lag" -lt "-$BLOCK_LAG_THRESHOLD" ]; then
  echo "Reference RPC is behind local node; treating local node as synced"
  exit 0
fi

echo "Node is syncing"
exit 1
