#!/usr/bin/bash

# Create Docker network
docker network create --internal vaultwarden

# Create directories
mkdir -p ${DATA_PATH}/vaultwarden/docker
mkdir -p ${DATA_PATH}/vaultwarden/configs
mkdir -p ${DATA_PATH}/vaultwarden/volumes/vaultwarden

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/vaultwarden/docker/docker-compose.yml << EOF
services:
  vaultwarden:
    image: vaultwarden/server:1.32.7
    pull_policy: always
    container_name: vaultwarden
    restart: always
    networks:
      - vaultwarden
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/vaultwarden/volumes/vaultwarden:/data

networks:
  vaultwarden:
    external: true
EOF

################################################
##### Environment variables
################################################

tee ${DATA_PATH}/vaultwarden/docker/config.env << EOF
ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
WEBSOCKET_ENABLED=true
SIGNUPS_ALLOWED=true
INVITATIONS_ALLOWED=false
SHOW_PASSWORD_HINT=false
EOF