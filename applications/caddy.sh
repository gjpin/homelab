#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Create directory
sudo mkdir -p /data/caddy

# Create Docker network
sudo docker network create caddy

# Create Docker volumes
sudo docker volume create caddy-data
sudo docker volume create caddy-config
sudo docker volume create caddy-webdav

# Generate WebDAV password
PASSWORD=$(openssl rand -hex 48)
HASHED_PASSWORD=$(sudo docker run caddy:2-alpine caddy hash-password --plaintext ${PASSWORD})

################################################
##### Kernel configurations
################################################

# References:
# https://github.com/lucas-clemente/quic-go/wiki/UDP-Receive-Buffer-Size

sudo sysctl net.core.rmem_max=2500000
sudo tee /etc/sysctl.d/99-udp-max-buffer-size.conf << EOF
net.core.rmem_max=2500000
EOF

################################################
##### Dockerfile
################################################

sudo tee /etc/selfhosted/caddy/Dockerfile << EOF
FROM caddy:2-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-webdav

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
EOF

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/caddy/docker-compose.yml << EOF
services:
  caddy:
    build:
      context: /etc/selfhosted/caddy
    container_name: caddy
    restart: always
    ports:
      - 443:443
    networks:
      - caddy
    volumes:
      - /etc/selfhosted/caddy/Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
      - caddy-webdav:/data/webdav

volumes:
  caddy-data:
    external: true
  caddy-config:
    external: true
  caddy-webdav:
    external: true

networks:
  caddy:
    external: true
EOF

################################################
##### Caddyfile
################################################

sudo tee /etc/selfhosted/caddy/Caddyfile << EOF
{
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

# WebDAV
webdav.${BASE_DOMAIN} {
    root * /data/webdav
    basicauth {
        admin ${HASHED_PASSWORD}
    }
    webdav
}
EOF