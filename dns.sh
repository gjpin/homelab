#!/usr/bin/bash

# Create networks (Caddy belongs to all networks)
sudo docker network create caddy --dns=1.1.1.1
sudo docker network create pihole --dns=1.1.1.1
sudo docker network create technitium --dns=1.1.1.1

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
envsubst < ./homelab/caddy/Dockerfile | tee ${DATA_PATH}/caddy/docker/Dockerfile > /dev/null
envsubst < ./homelab/caddy/docker-compose.yaml | tee ${DATA_PATH}/caddy/docker/docker-compose.yml > /dev/null
envsubst < ./homelab/caddy/Caddyfile | tee ${DATA_PATH}/caddy/configs/Caddyfile > /dev/null

# Install systemd service
envsubst < ./homelab/caddy/caddy.service | sudo tee /etc/systemd/system/caddy.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable caddy.service

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
envsubst < ./homelab/pihole/Dockerfile | tee ${DATA_PATH}/pihole/docker/Dockerfile > /dev/null
envsubst < ./homelab/pihole/docker-compose.yaml | tee ${DATA_PATH}/pihole/docker/docker-compose.yml > /dev/null
envsubst < ./homelab/pihole/config.env | tee ${DATA_PATH}/pihole/docker/config.env > /dev/null
envsubst < ./homelab/pihole/99-edns.conf | tee ${DATA_PATH}/pihole/configs/99-edns.conf > /dev/null

# Install systemd service
envsubst < ./homelab/pihole/pihole.service | sudo tee /etc/systemd/system/pihole.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable pihole.service

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
envsubst < ./homelab/technitium/docker-compose.yaml | tee ${DATA_PATH}/technitium/docker/docker-compose.yml > /dev/null
envsubst < ./homelab/technitium/config.env | tee ${DATA_PATH}/technitium/docker/config.env > /dev/null

# Install systemd service
envsubst < ./homelab/technitium/technitium.service | sudo tee /etc/systemd/system/technitium.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable technitium.service