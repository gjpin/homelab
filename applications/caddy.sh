#!/usr/bin/bash

# References:
# https://github.com/mholt/caddy-l4
# https://caddy.community/t/need-help-configuring-caddy-l4-for-git-ssh-access-on-domain/26405/7

# Create Docker network
docker network create caddy

# Create directories
mkdir -p ${DATA_PATH}/caddy/docker
mkdir -p ${DATA_PATH}/caddy/configs
mkdir -p ${DATA_PATH}/caddy/volumes/{caddy,bookmarks}

################################################
##### Dockerfile
################################################

tee ${DATA_PATH}/caddy/docker/Dockerfile << EOF
FROM caddy:2.9.1-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-webdav \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2.9.1-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
EOF

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/caddy/docker/docker-compose.yml << EOF
services:
  caddy:
    build:
      context: ${DATA_PATH}/caddy/docker
    container_name: caddy
    restart: always
    ports:
      - 443:443
    networks:
      - caddy
      - immich
      - obsidian
      - pihole
      - radicale
      - syncthing
      - vaultwarden
      - gitea
      - librechat
    volumes:
      - ${DATA_PATH}/caddy/configs/Caddyfile:/etc/caddy/Caddyfile
      - ${DATA_PATH}/caddy/volumes/caddy:/data/caddy
      - ${DATA_PATH}/caddy/volumes/bookmarks:/data/bookmarks

networks:
  caddy:
    external: true
  immich:
    external: true
  obsidian:
    external: true
  pihole:
    external: true
  radicale:
    external: true
  syncthing:
    external: true
  vaultwarden:
    external: true
  gitea:
    external: true
  librechat:
    external: true
EOF

################################################
##### Caddyfile
################################################

tee ${DATA_PATH}/caddy/configs/Caddyfile << EOF
{
        acme_dns cloudflare ${CADDY_CLOUDFLARE_TOKEN}
        order webdav before file_server
}

(default-header) {
        header {
                # Disable FLoC tracking
                Permissions-Policy "interest-cohort=()"

                # Enable HSTS
                Strict-Transport-Security "max-age=31536000;"

                # Disable clients from sniffing the media type
                X-Content-Type-Options "nosniff"

                # Clickjacking protection
                X-Frame-Options "SAMEORIGIN"

                # Enable cross-site filter (XSS) and tell browser to block detected attacks
                X-XSS-Protection "1; mode=block"

                # Prevent search engines from indexing
                X-Robots-Tag "none"

                # Remove X-Powered-By header
                -X-Powered-By

                # Remove Server header
                -Server
        }
}

# WebDAV - Bookmarks
bookmarks.${BASE_DOMAIN} {
    root * /data/bookmarks
    basicauth {
        admin ${CADDY_HASHED_PASSWORD}
    }
    webdav
}

# Immich
photos.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy immich-server:2283 {
                header_up X-Real-IP {remote_host}
        }
}

# Obsidian
obsidian.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy obsidian:5984 {
                header_up X-Real-IP {remote_host}
        }
}

# Pi-hole
pihole.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy pihole:80 {
                header_up X-Real-IP {remote_host}
        }
}

# Technitium
technitium.${BASE_DOMAIN} {
        import default-header

        encode gzip

        # Web Console (HTTP)
        reverse_proxy technitium:5380 {
                header_up X-Real-IP {remote_host}
        }
}

# Radicale
contacts.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy radicale:5232 {
                header_up X-Real-IP {remote_host}
        }
}

# Syncthing
syncthing.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy syncthing:8384 {
                header_up X-Real-IP {remote_host}
        }
}

# Vaultwarden
vault.${BASE_DOMAIN} {
        import default-header

        encode gzip

        # Vaultwarden HTTP server
        reverse_proxy vaultwarden:80 {
                header_up X-Real-IP {remote_host}
        }

        # Websockets server
        reverse_proxy /notifications/hub vaultwarden:3012 {
                header_up X-Real-IP {remote_host}
        }

        # Negotiation endpoint
        reverse_proxy /notifications/hub/negotiate vaultwarden:8080 {
                header_up X-Real-IP {remote_host}
        }
}

# Gitea
git.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy gitea:3000 {
                header_up X-Real-IP {remote_host}
        }
}

# Librechat
chat.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy librechat:3080 {
                header_up X-Real-IP {remote_host}
        }
}
EOF