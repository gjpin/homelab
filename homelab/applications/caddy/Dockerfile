# https://hub.docker.com/_/caddy
FROM docker.io/caddy:2.10.2-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-webdav \
    --with github.com/caddy-dns/cloudflare

FROM docker.io/caddy:2.10.2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy