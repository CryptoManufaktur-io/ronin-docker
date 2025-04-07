# Overview

Docker Compose for Ronin node.

The `./ronind` script can be used as a quick-start:

`./ronind install` brings in docker-ce, if you don't have Docker installed already.

`cp default.env .env`

`nano .env` and adjust variables as needed, particularly `PASSWORD`, `SNAPSHOT` and `INSTANCE_NAME`

`./ronind up`

To update the software, run `./ronind update` and then `./ronind up`

If you want the ronin RPC ports exposed, use `rpc-shared.yml` in `COMPOSE_FILE` inside `.env`.

If meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

This is Ronin Docker v1.1.1
