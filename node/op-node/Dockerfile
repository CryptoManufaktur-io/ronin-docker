ARG OP_NODE_DOCKER_TAG=v1.16.5
FROM us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:${OP_NODE_DOCKER_TAG} AS opnode

FROM ubuntu:24.04

COPY --from=opnode /usr/local/bin/op-node /usr/local/bin/op-node
COPY download-consensus-layer-files.sh /usr/local/bin/download-consensus-layer-files.sh

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl jq \
  && chmod +x /usr/local/bin/download-consensus-layer-files.sh \
  && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/local/bin/download-consensus-layer-files.sh"]
