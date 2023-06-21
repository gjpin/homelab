#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# References:
# https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/setup_own_server.md

# Create directory
sudo mkdir -p /etc/selfhosted/obsidian

# Create Docker network
sudo docker network create obsidian

# Create Docker volumes
sudo docker volume create obsidian

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/obsidian/docker-compose.yml << EOF
services:
  obsidian:
    image: couchdb:latest
    container_name: obsidian
    restart: always
    networks:
      - obsidian
      - caddy
    volumes:
      - /etc/selfhosted/obsidian/local.ini:/opt/couchdb/etc/local.ini
      - obsidian:/opt/couchdb/data
    env_file:
      - config.env

volumes:
  obsidian:
    external: true

networks:
  obsidian:
    external: true
  caddy:
    external: true
EOF

################################################
##### Environment variables
################################################

sudo tee /etc/selfhosted/obsidian/config.env << EOF
COUCHDB_USER=admin
COUCHDB_PASSWORD=$(openssl rand -hex 48)
EOF

################################################
##### CouchDB configuration
################################################

sudo tee /etc/selfhosted/obsidian/local.ini << EOF
[couchdb]
single_node=true
max_document_size = 50000000

[chttpd]
require_valid_user = true
max_http_request_size = 4294967296

[chttpd_auth]
require_valid_user = true
authentication_redirect = /_utils/session.html

[httpd]
WWW-Authenticate = Basic realm="couchdb"
enable_cors = true

[cors]
origins = app://obsidian.md,capacitor://localhost,http://localhost
credentials = true
headers = accept, authorization, content-type, origin, referer
methods = GET, PUT, POST, HEAD, DELETE
max_age = 3600
EOF

################################################
##### Caddyfile
################################################

sudo tee -a /etc/selfhosted/caddy/Caddyfile << EOF

# Obsidian
obsidian.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy obsidian:5984 {
                header_up X-Real-IP {remote_host}
        }
}
EOF