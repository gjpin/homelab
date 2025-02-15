#!/usr/bin/bash

# References:
# https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/setup_own_server.md

# Create Docker network
sudo podman network create --internal obsidian

# Create directories
mkdir -p ${DATA_PATH}/obsidian/docker
mkdir -p ${DATA_PATH}/obsidian/configs
mkdir -p ${DATA_PATH}/obsidian/volumes/obsidian

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/obsidian/docker/docker-compose.yml << EOF
services:
  obsidian:
    image: docker.io/couchdb:latest
    container_name: obsidian
    volumes:
      - ${DATA_PATH}/obsidian/configs/local.ini:/opt/couchdb/etc/local.ini:Z
      - ${DATA_PATH}/obsidian/volumes/obsidian:/opt/couchdb/data:Z
    env_file:
      - config.env
    restart: always
    networks:
      - obsidian

networks:
  obsidian:
    external: true
EOF

################################################
##### Environment variables
################################################

tee ${DATA_PATH}/obsidian/docker/config.env << EOF
COUCHDB_USER=admin
COUCHDB_PASSWORD=${OBSIDIAN_COUCHDB_PASSWORD}
EOF

################################################
##### CouchDB configuration
################################################

tee ${DATA_PATH}/obsidian/configs/local.ini << EOF
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