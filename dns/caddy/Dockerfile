FROM docker.io/caddy:2.10.0-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM docker.io/caddy:2.10.0-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy