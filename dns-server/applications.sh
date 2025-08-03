#!/usr/bin/bash

# Env vars
export DATA_PATH=${HOME}/containers

# Create networks (Caddy belongs to all networks)
sudo docker network create caddy
sudo docker network create pihole
sudo docker network create technitium

################################################
##### Env vars
################################################

# Store main env vars
cat <<EOF >> "${HOME}/.bashrc.d/env"
export BASE_DOMAIN=${BASE_DOMAIN}
export DATA_PATH="${DATA_PATH}"

# Caddy
export CADDY_HASHED_PASSWORD='${CADDY_HASHED_PASSWORD}'
export CADDY_CLOUDFLARE_TOKEN='${CADDY_CLOUDFLARE_TOKEN}'

# Pi-Hole
export PIHOLE_ADMIN_TOKEN='${PIHOLE_ADMIN_TOKEN}'
export PIHOLE_WEBPASSWORD='${PIHOLE_WEBPASSWORD}'

# Technitium
export TECHNITIUM_ADMIN_PASSWORD='${TECHNITIUM_ADMIN_PASSWORD}'
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
envsubst < ./dns/caddy/Dockerfile | tee ${DATA_PATH}/caddy/docker/Dockerfile > /dev/null
envsubst < ./dns/caddy/docker-compose.yaml | tee ${DATA_PATH}/caddy/docker/docker-compose.yml > /dev/null
envsubst < ./dns/caddy/Caddyfile | tee ${DATA_PATH}/caddy/configs/Caddyfile > /dev/null

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
envsubst < ./dns/pihole/Dockerfile | tee ${DATA_PATH}/pihole/docker/Dockerfile > /dev/null
envsubst < ./dns/pihole/docker-compose.yaml | tee ${DATA_PATH}/pihole/docker/docker-compose.yml > /dev/null
envsubst < ./dns/pihole/config.env | tee ${DATA_PATH}/pihole/docker/config.env > /dev/null
envsubst < ./dns/pihole/99-edns.conf | tee ${DATA_PATH}/pihole/configs/99-edns.conf > /dev/null

################################################
##### Technitium
################################################

# References:
# https://technitium.com/dns/help.html
# https://technitium.com/dns/
# https://hub.docker.com/r/technitium/dns-server
# https://github.com/TechnitiumSoftware/DnsServer
# https://github.com/TechnitiumSoftware/DnsServer/blob/master/docker-compose.yml

# Create directories
mkdir -p ${DATA_PATH}/technitium/docker
mkdir -p ${DATA_PATH}/technitium/configs
mkdir -p ${DATA_PATH}/technitium/volumes/technitium

# Copy files to expected directories and expand variables
envsubst < ./dns/technitium/docker-compose.yaml | tee ${DATA_PATH}/technitium/docker/docker-compose.yml > /dev/null
envsubst < ./dns/technitium/config.env | tee ${DATA_PATH}/technitium/docker/config.env > /dev/null