#!/usr/bin/env sh
set -eu

if [ -f /ronin/prune-marker ]; then
  rm -f /ronin/prune-marker
  exec ronin snapshot prune-state --datadir /ronin/data
else
  exec "$@"
fi
