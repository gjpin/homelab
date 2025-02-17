FROM docker.io/caddy:2.9.1-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-webdav \
    --with github.com/caddy-dns/cloudflare

FROM docker.io/caddy:2.9.1-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy