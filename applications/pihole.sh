#!/usr/bin/bash

# References:
# https://github.com/pi-hole/docker-pi-hole/

# Create Docker network
sudo docker network create pihole

# Create directories
mkdir -p ${DATA_PATH}/pihole/docker
mkdir -p ${DATA_PATH}/pihole/configs
mkdir -p ${DATA_PATH}/pihole/volumes/pihole

################################################
##### Dockerfile
################################################

# Create DNSCrypt image
tee ${DATA_PATH}/pihole/docker/Dockerfile << EOF
FROM alpine:edge

RUN apk update && \
    apk add dnscrypt-proxy dnscrypt-proxy-openrc && \
    sed -i "s|^listen_addresses.*$|listen_addresses = ['0.0.0.0:53']|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^doh_servers.*$|doh_servers = true|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^dnscrypt_servers.*$|dnscrypt_servers = false|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^require_dnssec.*$|require_dnssec = true|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml

ENTRYPOINT dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml
EOF

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/pihole/docker/docker-compose.yml << EOF
services:
  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: always
    networks:
      - pihole
    ports:
      - 53:53/tcp
      - 53:53/udp
    env_file:
      - config.env
    depends_on:
      - pihole-dnscrypt
    volumes:
      - ${DATA_PATH}/pihole/volumes/pihole:/etc/pihole
      - ${DATA_PATH}/pihole/configs/99-edns.conf:/etc/dnsmasq.d/99-edns.conf

  pihole-dnscrypt:
    build:
      context: ${DATA_PATH}/pihole/docker
    container_name: pihole-dnscrypt
    restart: always
    networks:
      - pihole

networks:
  pihole:
    external: true
EOF

################################################
##### Environment variables
################################################

tee ${DATA_PATH}/pihole/docker/config.env << EOF
ADMIN_TOKEN=${PIHOLE_ADMIN_TOKEN}
WEBPASSWORD=${PIHOLE_WEBPASSWORD}
FTLCONF_LOCAL_IPV4=$(ip addr show wlan0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
TZ=$(cat /etc/timezone)
VIRTUAL_HOST=pihole.${BASE_DOMAIN}
DNSMASQ_LISTENING=all
PIHOLE_DNS_=pihole-dnscrypt#53
DNSSEC=false
DNSMASQ_USER=root
EOF

################################################
##### Configurations
################################################

# Import dnsmasq's configuration file
tee ${DATA_PATH}/pihole/configs/99-edns.conf << EOF
edns-packet-max=1232
EOF

# Disable the DNSStubListener to unbind it from port 53
sudo sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved