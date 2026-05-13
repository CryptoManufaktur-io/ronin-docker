#!/usr/bin/env sh
set -eu

if [ -z "${RETH_SEQUENCER_URL:-}" ]; then
  echo "RETH_SEQUENCER_URL must be set"
  exit 1
fi

set -- \
  --datadir=/data \
  --chain=/data/genesis.json \
  --rollup.sequencer="${RETH_SEQUENCER_URL}" \
  --http \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=admin,debug,eth,net,trace,txpool,web3 \
  --ws \
  --ws.addr=0.0.0.0 \
  --ws.port=8546 \
  --ws.origins="*" \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=9551 \
  --authrpc.jwtsecret=/data/jwt.hex \
  "$@"

if [ -n "${RETH_HISTORICAL_RPC:-}" ]; then
  set -- --rollup.historicalrpc="${RETH_HISTORICAL_RPC}" "$@"
fi

exec op-reth node "$@"
