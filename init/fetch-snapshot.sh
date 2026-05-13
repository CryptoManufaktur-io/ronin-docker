#!/usr/bin/env bash
set -euo pipefail

DATADIR="${DATADIR:-/data}"

case "${NETWORK:-}" in
  ronin)
    conduit_slug="ronin-mainnet-bfz9fadqzl"
    bedrock_block=55577500
    ;;
  saigon)
    conduit_slug="saigon-testnet-cc58e966ql"
    bedrock_block=45528550
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

SNAPSHOT="${SNAPSHOT:-https://storage.googleapis.com/conduit-networks-snapshots/${conduit_slug}/latest.tar}"
genesis_url="https://api.conduit.xyz/file/v1/optimism/genesis/${conduit_slug}"
db_path="${DATADIR}/db/mdbx.dat"
genesis_path="${DATADIR}/genesis.json"
jwt_path="${DATADIR}/jwt.hex"

flatten_mnt_dir() {
  local source_dir="$1"
  echo "Flattening ${source_dir} into ${DATADIR}"
  shopt -s dotglob nullglob
  for path in "${source_dir}"/*; do
    target="${DATADIR}/$(basename "$path")"
    if [ -e "$target" ]; then
      echo "Refusing to overwrite existing ${target}"
      exit 1
    fi
    mv "$path" "${DATADIR}/"
  done
  rmdir "$source_dir"
}

normalize_snapshot_layout() {
  if [ -f "$db_path" ]; then
    return 0
  fi

  if [ -f "${DATADIR}/mnt/db/mdbx.dat" ]; then
    flatten_mnt_dir "${DATADIR}/mnt"
    return 0
  fi

  if [ -f "${DATADIR}/data/ronin/mnt/db/mdbx.dat" ]; then
    flatten_mnt_dir "${DATADIR}/data/ronin/mnt"
    return 0
  fi
}

mkdir -p "$DATADIR"
normalize_snapshot_layout

if [ ! -f "$db_path" ]; then
  echo "Downloading snapshot into ${DATADIR}"
  curl -fL --retry 5 --retry-delay 5 "$SNAPSHOT" | tar -xvf - -C "$DATADIR" --strip-components=1
  normalize_snapshot_layout
fi

if [ ! -f "$db_path" ]; then
  echo "Reth database is not in the expected location: ${db_path}"
  echo "The snapshot must end up with db/mdbx.dat directly under DATADIR."
  exit 1
fi

if [ ! -f "$genesis_path" ]; then
  echo "Downloading genesis.json into ${DATADIR}"
  curl -fL --retry 5 --retry-delay 5 "$genesis_url" -o "$genesis_path"
fi

if [ "${UPDATE_BEDROCK_BLOCK:-false}" = "true" ]; then
  echo "Setting genesis bedrockBlock to ${bedrock_block}"
  jq --argjson block "$bedrock_block" '.config.bedrockBlock = $block' "$genesis_path" > "${genesis_path}.tmp"
  mv "${genesis_path}.tmp" "$genesis_path"
fi

if [ ! -f "$jwt_path" ]; then
  echo "Generating JWT secret at ${jwt_path}"
  openssl rand -hex 32 > "$jwt_path"
fi

echo "Ronin reth datadir is ready at ${DATADIR}"
