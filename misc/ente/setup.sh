#!/usr/bin/bash

# Create networks
docker network create --internal ente

################################################
##### Env vars
################################################

# Ente
export ENTE_DATABASE_PASSWORD=$(openssl rand -hex 48)
export ENTE_KEY_ENCRYPTION=$(openssl rand -base64 32)
export ENTE_KEY_HASH=$(openssl rand -base64 64 | tr -d '\n')
export ENTE_JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')

cat <<EOF >> "${HOME}/.bashrc.d/env"
# Ente
export ENTE_DATABASE_PASSWORD='${ENTE_DATABASE_PASSWORD}'
export ENTE_KEY_ENCRYPTION='${ENTE_KEY_ENCRYPTION}'
export ENTE_KEY_HASH='${ENTE_KEY_HASH}'
export ENTE_JWT_SECRET='${ENTE_JWT_SECRET}'
EOF

################################################
##### Ente
################################################

# References:
# https://help.ente.io/self-hosting/installation/env-var
# https://github.com/ente-io/ente/blob/main/server/config/example.env
# https://github.com/ente-io/ente/blob/main/server/config/compose.yaml
# https://github.com/ente-io/ente/blob/main/web/docs/docker.md
# https://help.ente.io/self-hosting/installation/config

# Create directories
mkdir -p ${DATA_PATH}/ente/docker
mkdir -p ${DATA_PATH}/ente/volumes/{ente,postgres}
mkdir -p ${DATA_PATH}/ente/configs

# Copy files to expected directories and expand variables
envsubst < ./applications/ente/docker-compose.yaml | tee ${DATA_PATH}/ente/docker/docker-compose.yml > /dev/null
envsubst < ./applications/ente/config.env | tee ${DATA_PATH}/ente/docker/config.env > /dev/null
envsubst < ./applications/ente/museum.yaml | tee ${DATA_PATH}/ente/configs/museum.yaml > /dev/null
