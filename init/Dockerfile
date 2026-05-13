FROM alpine:3.20

COPY fetch-snapshot.sh /usr/local/bin/

RUN apk add --no-cache bash ca-certificates curl jq openssl tar

ENTRYPOINT [ "fetch-snapshot.sh" ]
