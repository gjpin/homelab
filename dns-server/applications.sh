#!/usr/bin/bash

# Env vars
export DATA_PATH=${HOME}/containers

# Create networks (Caddy belongs to all networks)
sudo docker network create caddy
sudo docker network create dnscrypt
sudo docker network create pihole
sudo docker network create technitium

################################################
##### Env vars
################################################

# Store main env vars
cat <<EOF > "${HOME}/.bashrc.d/env"
export BASE_DOMAIN=${BASE_DOMAIN}
export DATA_PATH="${DATA_PATH}"

# Caddy
export CADDY_HASHED_PASSWORD='${CADDY_HASHED_PASSWORD}'
export CADDY_CLOUDFLARE_TOKEN='${CADDY_CLOUDFLARE_TOKEN}'

# Pi-Hole
export PIHOLE_ADMIN_TOKEN='${PIHOLE_ADMIN_TOKEN}'
export PIHOLE_WEBPASSWORD='${PIHOLE_WEBPASSWORD}'

# dnscrypt
export DNSCRYPT_UI_USER='${DNSCRYPT_UI_USER}'
export DNSCRYPT_UI_PASSWORD='${DNSCRYPT_UI_PASSWORD}'
EOF

################################################
##### Caddy
################################################

# References:
# https://github.com/mholt/caddy-l4
# https://caddy.community/t/need-help-configuring-caddy-l4-for-git-ssh-access-on-domain/26405/7

# Create directories
mkdir -p ${DATA_PATH}/caddy/docker
mkdir -p ${DATA_PATH}/caddy/configs
mkdir -p ${DATA_PATH}/caddy/volumes/{caddy,bookmarks}

# Copy files to expected directories and expand variables
envsubst < ./applications/caddy/Dockerfile | tee ${DATA_PATH}/caddy/docker/Dockerfile > /dev/null
envsubst < ./applications/caddy/docker-compose.yaml | tee ${DATA_PATH}/caddy/docker/docker-compose.yml > /dev/null
envsubst < ./applications/caddy/Caddyfile | tee ${DATA_PATH}/caddy/configs/Caddyfile > /dev/null

################################################
##### dnscrypt
################################################

# References:
# https://dnscrypt.info/doc
# https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml

# Create directories
mkdir -p ${DATA_PATH}/dnscrypt/docker
mkdir -p ${DATA_PATH}/dnscrypt/configs

# Copy files to expected directories and expand variables
envsubst < ./applications/dnscrypt/Dockerfile | tee ${DATA_PATH}/dnscrypt/docker/Dockerfile > /dev/null
envsubst < ./applications/dnscrypt/docker-compose.yaml | tee ${DATA_PATH}/dnscrypt/docker/docker-compose.yml > /dev/null
envsubst < ./applications/dnscrypt/dnscrypt-proxy.toml | tee ${DATA_PATH}/dnscrypt/configs/dnscrypt-proxy.toml > /dev/null

################################################
##### Pi-Hole
################################################

# References:
# https://github.com/pi-hole/docker-pi-hole/

# Create directories
mkdir -p ${DATA_PATH}/pihole/docker
mkdir -p ${DATA_PATH}/pihole/configs
mkdir -p ${DATA_PATH}/pihole/volumes/pihole

# Copy files to expected directories and expand variables
envsubst < ./applications/pihole/docker-compose.yaml | tee ${DATA_PATH}/pihole/docker/docker-compose.yml > /dev/null
envsubst < ./applications/pihole/config.env | tee ${DATA_PATH}/pihole/docker/config.env > /dev/null
envsubst < ./applications/pihole/99-edns.conf | tee ${DATA_PATH}/pihole/configs/99-edns.conf > /dev/null