#!/usr/bin/bash

# References:
# https://github.com/syncthing/syncthing/blob/main/README-Docker.md

# Create Docker network
sudo podman network create syncthing

# Create directories
mkdir -p ${DATA_PATH}/syncthing/docker
mkdir -p ${DATA_PATH}/syncthing/configs
mkdir -p ${DATA_PATH}/syncthing/volumes/syncthing

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/syncthing/docker/docker-compose.yml << EOF
services:
  syncthing:
    image: docker.io/syncthing/syncthing:1.29.2
    pull_policy: always
    container_name: syncthing
    hostname: ${HOSTNAME}
    restart: always
    environment:
      - PUID=1000
      - PGID=1000
    networks:
      - syncthing
    volumes:
      - ${DATA_PATH}/syncthing/volumes/syncthing:/var/syncthing:Z
    ports:
      - 22000:22000/tcp
      - 22000:22000/udp
      - 21027:21027/udp

networks:
  syncthing:
    external: true
EOF