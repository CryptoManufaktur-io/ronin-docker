# Ronin Docker

Docker Compose for a current Ronin mainnet RPC node using Conduit's OP Stack
setup: Conduit op-reth, OP Labs op-node, and EigenDA proxy. This follows the
x-docker layout: `ethd` is the canonical helper and `ronind` is the protocol
alias symlink.

References:

- Ronin node setup: https://docs.roninchain.com/developers/nodes/setup
- Conduit Ronin migration compose: https://github.com/conduitxyz/ronin-migration-reth-docker

## Services

- `ronin-init` restores the official Conduit snapshot, downloads genesis, sets
  the Ronin Bedrock block, and creates the execution JWT secret.
- `ronin-execution` runs Conduit's `op-reth` build and serves JSON-RPC and WS.
- `ronin-op-node` derives the chain from Ethereum L1 and drives the execution
  engine.
- `ronin-eigenda-proxy` provides the EigenDA alternative DA endpoint used by
  op-node.

Image-specific Dockerfiles and entrypoints live under `node/reth/` and
`node/op-node/`; the `init/` directory only handles snapshot preparation.

This is not the old Ronin geth layout. The datadir is expected to contain
`db/mdbx.dat`, `static_files/`, `genesis.json`, and `jwt.hex`; there is no
`chaindata` directory.

Current component pins match Conduit's published setup:

- `ghcr.io/conduitxyz/conduit-op-reth:v1.0.0-rc.1`
- `us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.16.5`
- `ghcr.io/layr-labs/eigenda-proxy:2.7.0`

Conduit's mainnet resource guidance is 2 CPU, 120 GiB memory, and 800 GiB disk.

## Command Reference

| Command | Description |
|---------|-------------|
| `./ethd install` | Install Docker prerequisites on Debian/Ubuntu |
| `./ethd build` | Build the Ronin init, op-reth, and op-node images |
| `./ethd up` / `start` / `run` | Start or recreate the Ronin services |
| `./ethd down` / `stop` | Stop services without deleting data |
| `./ethd restart` | Stop and start services |
| `./ethd logs` | Show Compose logs |
| `./ethd init-logs` | Show snapshot/init logs |
| `./ethd ps` / `status` | Show containers and basic RPC status |
| `./ethd check-sync` | Check execution head, chain ID, block hash, OP Stack sync status, and peers |
| `./ethd version` | Show script and client versions |
| `./ethd update` | Pull repo updates, migrate `.env`, pull/build images |
| `./ethd terminate` | Destructively stop services and remove Ronin data after confirmation |
| `./ethd config` | Render the Docker Compose config |
| `./ethd cmd <args>` | Pass arguments directly to Docker Compose |

Update options match the x-docker skeleton:

```sh
./ethd update --refresh-targets
./ethd update --non-interactive
./ethd update --debug
```

## Quick Start

Install Docker Engine and the Docker Compose plugin, then configure the node:

```sh
cp default.env .env
nano .env
```

Set at least these values in `.env`:

- `DATADIR`: persistent host path for the Ronin reth data.
- `OP_NODE_L1_ETH_RPC`: Ethereum L1 execution RPC URL.
- `OP_NODE_L1_BEACON`: Ethereum consensus/beacon API URL.
- `RETH_SEQUENCER_URL`: Conduit Ronin sequencer RPC. The public URL is useful
  for bootstrap, but production nodes should use an API-key URL from Conduit to
  avoid rate limits on forwarded transactions.
- `RETH_HISTORICAL_RPC`: optional endpoint for pre-Bedrock historical queries.
  Current post-migration head sync can run without it.
- `RPC_HOST`, `WS_HOST`, and `DOMAIN`: Traefik hostnames, if using
  `ext-network.yml`.

`OP_NODE_P2P_STATIC` is set to the current Ronin peer from Conduit's README.
`op-node` also accepts a comma-separated static peer list if Conduit publishes
additional peers later.

Build and start:

```sh
./ethd build
./ethd up
```

Check startup and sync:

```sh
./ethd init-logs
./ethd status
./ethd check-sync
```

Use `COMPOSE_FILE=ronin.yml:rpc-shared.yml` to expose RPC and WS on
`127.0.0.1` from the host. Use `COMPOSE_FILE=ronin.yml:ext-network.yml` when
the node is behind central-proxy/Traefik; that overlay attaches
`ronin-execution` to the external network and applies the Traefik labels.

`ronin-execution` and `ronin-op-node` include Compose healthchecks. `up` waits
for init completion and execution health before starting op-node.

## Snapshot

The current official snapshot is:

```text
https://storage.googleapis.com/conduit-networks-snapshots/ronin-mainnet-bfz9fadqzl/latest.tar
```

The snapshot extracts as a Conduit/Reth tree under `mnt/`. The init script
normalizes that into the configured `DATADIR` so op-reth sees `db/mdbx.dat`
directly under the datadir.

If a previous restore left data under `DATADIR/data/ronin/mnt`, rerunning
`ronin-init` will flatten that failed layout as well.

## Updates

Change image tags in `.env`, then rebuild and restart:

```sh
./ethd build
./ethd up
```

Run `./ethd update` to pull repo changes, migrate `.env` to the current
`ENV_VERSION`, pull upstream images, and rebuild local images. If migration
changes `.env`, the previous file is preserved as `.env.bak`.

`./ethd down -v` is intentionally blocked. Use `./ethd terminate` for
destructive cleanup; it asks for explicit confirmation before removing Docker
volumes and `DATADIR`.

`./ronind` can be used anywhere `./ethd` appears; it is kept as the
Ronin-specific convenience alias.

This is Ronin Docker v2.0.0
