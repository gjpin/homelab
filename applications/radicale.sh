#!/usr/bin/bash

# References:
# https://radicale.org/v3.html#basic-configuration
# https://caddy.community/t/radicale-reverse-proxy-caddy-2-0/8580/5

# Create Docker network
sudo podman network create --internal radicale

# Create directories
mkdir -p ${DATA_PATH}/radicale/docker
mkdir -p ${DATA_PATH}/radicale/configs
mkdir -p ${DATA_PATH}/radicale/volumes/radicale

################################################
##### Dockerfile
################################################

tee ${DATA_PATH}/radicale/docker/Dockerfile << EOF
FROM docker.io/alpine:edge

RUN apk add --update --no-cache radicale py3-bcrypt

ENTRYPOINT ["radicale"]
EOF

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/radicale/docker/docker-compose.yml << EOF
services:
  radicale:
    build:
      context: ${DATA_PATH}/radicale/docker
    container_name: radicale
    restart: always
    networks:
      - radicale
    volumes:
      - ${DATA_PATH}/radicale/configs/users:/etc/radicale/users:Z
      - ${DATA_PATH}/radicale/configs/config:/etc/radicale/config:Z
      - ${DATA_PATH}/radicale/volumes/radicale:/var/lib/radicale/collections:Z

networks:
  radicale:
    external: true
EOF

################################################
##### Configurations
################################################

# Create user
tee ${DATA_PATH}/radicale/configs/users << EOF
${RADICALE_USER_PASSWORD}
EOF

# Create configuration
tee ${DATA_PATH}/radicale/configs/config << EOF
[auth]
type = htpasswd
htpasswd_filename = /etc/radicale/users
htpasswd_encryption = bcrypt

[server]
hosts = 0.0.0.0:5232, [::]:5232
EOF