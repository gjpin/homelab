#!/usr/bin/bash

# References:
# https://technitium.com/dns/help.html
# https://technitium.com/dns/
# https://hub.docker.com/r/technitium/dns-server
# https://github.com/TechnitiumSoftware/DnsServer
# https://github.com/TechnitiumSoftware/DnsServer/blob/master/docker-compose.yml

# Create Docker network
sudo podman network create technitium

# Create directories
mkdir -p ${DATA_PATH}/technitium/docker
mkdir -p ${DATA_PATH}/technitium/configs
mkdir -p ${DATA_PATH}/technitium/volumes/technitium

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/technitium/docker/docker-compose.yml << EOF
services:
  technitium:
    image: docker.io/technitium/dns-server:13.3.0
    pull_policy: always
    container_name: technitium
    restart: always
    hostname: technitium
    networks:
      - technitium
    ports:
      - 53:53/tcp
      - 53:53/udp
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/technitium/volumes/technitium:/etc/dns:Z
    sysctls:
      - net.ipv4.ip_local_port_range=1024 65000

networks:
  technitium:
    external: true
EOF

################################################
##### Environment variables
################################################

tee ${DATA_PATH}/technitium/docker/config.env << EOF
DNS_SERVER_DOMAIN=technitium.${BASE_DOMAIN}
DNS_SERVER_ADMIN_PASSWORD=${TECHNITIUM_ADMIN_PASSWORD}
EOF