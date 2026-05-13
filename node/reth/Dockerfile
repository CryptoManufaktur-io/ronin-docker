ARG RETH_DOCKER_TAG=v1.0.0-rc.1
FROM ghcr.io/conduitxyz/conduit-op-reth:${RETH_DOCKER_TAG}

COPY start-reth.sh /usr/local/bin/start-reth.sh

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl jq \
  && chmod +x /usr/local/bin/start-reth.sh \
  && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/local/bin/start-reth.sh"]
