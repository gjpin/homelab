#!/usr/bin/bash

# References:
# https://docs.gitea.com/installation/install-with-docker-rootless
# https://caddy.community/t/need-help-configuring-caddy-l4-for-git-ssh-access-on-domain/26405/2

# Create Docker network
sudo podman network create gitea --dns=1.1.1.1

# Create directories
mkdir -p ${DATA_PATH}/gitea/docker
mkdir -p ${DATA_PATH}/gitea/configs
mkdir -p ${DATA_PATH}/gitea/volumes/{gitea,postgres}

# Fix permissions
sudo chown -R 1000:1000 ${DATA_PATH}/gitea/configs
sudo chown -R 1000:1000 ${DATA_PATH}/gitea/volumes/gitea

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/gitea/docker/docker-compose.yml << EOF
services:
  gitea:
    image: docker.io/gitea/gitea:1.23.3
    pull_policy: always
    container_name: gitea
    restart: always
    networks:
      - gitea
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/gitea/volumes/gitea:/data:Z
    depends_on:
      - gitea-postgres

  gitea-postgres:
    container_name: gitea-postgres
    image: docker.io/postgres:17.2-bookworm
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/gitea/volumes/postgres:/var/lib/postgresql/data:Z
    restart: always
    networks:
      - gitea

networks:
  gitea:
    external: true
EOF

################################################
##### Environment variables
################################################

tee ${DATA_PATH}/gitea/docker/config.env << EOF
# Postgres
POSTGRES_PASSWORD=${GITEA_DATABASE_PASSWORD}
POSTGRES_USER=gitea
POSTGRES_DB=gitea

# Gitea
USER_UID=1000
USER_GID=1000

GITEA__database__DB_TYPE=postgres
GITEA__database__HOST=gitea-postgres
GITEA__database__NAME=gitea
GITEA__database__USER=gitea
GITEA__database__PASSWD=${GITEA_DATABASE_PASSWORD}
EOF