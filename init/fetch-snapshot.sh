#!/usr/bin/env bash
set -euo pipefail

# Prep datadir
if [ -n "${SNAPSHOT}" ] && [ ! -d "/ronin/data/ronin" ]; then
  __dont_rm=0
  mkdir -p /ronin/snapshot
  mkdir -p /ronin/data/ronin
  cd /ronin/snapshot
  eval "__url=${SNAPSHOT}"
# shellcheck disable=SC2154
  if [[ "${__url}" == "https://storage.cloud.google.com/"* ]]; then
    echo "Google Cloud URL detected, using gsutil"
    __path="gs://${__url#https://storage.cloud.google.com/}"
    gsutil -m cp "${__path}" .
  else
    aria2c -c -x6 -s6 --auto-file-renaming=false --conditional-get=true --allow-overwrite=true "${__url}"
  fi
  echo "Copy completed, extracting"
  filename=$(echo "${__url}" | awk -F/ '{print $NF}')
  if [[ "${filename}" =~ \.tar\.zst$ ]]; then
    pzstd -c -d "${filename}" | tar xvf - -C /ronin/data/ronin
  elif [[ "${filename}" =~ \.tar\.gz$ || "${filename}" =~ \.tgz$ ]]; then
    tar xzvf "${filename}" -C /ronin/data/ronin
  elif [[ "${filename}" =~ \.tar$ ]]; then
    tar xvf "${filename}" -C /ronin/data/ronin
  elif [[ "${filename}" =~ \.lz4$ ]]; then
    lz4 -d "${filename}" | tar xvf - -C /ronin/data/ronin
  else
    __dont_rm=1
    echo "The snapshot file has a format that Ronin Docker can't handle."
    echo "Please come to CryptoManufaktur Discord to work through this."
  fi
  if [ "${__dont_rm}" -eq 0 ]; then
    rm -f "${filename}"
  fi
  # try to find the directory
  __search_dir="ronin/chaindata"
  __base_dir="/ronin/data/"
  __found_path=$(find "$__base_dir" -type d -path "*/$__search_dir" -print -quit)
  if [ -n "$__found_path" ]; then
    __geth_dir=$(dirname "$__found_path")
    __geth_dir=${__geth_dir%/chaindata}
    if [ "${__geth_dir}" = "${__base_dir}ronin" ]; then
       echo "Snapshot extracted into ${__geth_dir}/chaindata"
    else
      echo "Found a ronin directory at ${__geth_dir}, moving it."
      mv "$__geth_dir" "$__base_dir"
      rm -rf "$__geth_dir"
    fi
  fi
  if [[ ! -d /ronin/data/ronin/chaindata ]]; then
    echo "Chaindata isn't in the expected location."
    echo "This snapshot likely won't work until the entrypoint script has been adjusted for it."
    exit 1
  fi
else
  echo "No snapshot fetch necessary"
fi
