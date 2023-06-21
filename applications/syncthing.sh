#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# References:
# https://github.com/syncthing/syncthing/blob/main/README-Docker.md

# Create directories
sudo mkdir -p /etc/selfhosted/syncthing
mkdir -p ${HOME}/syncthing

# Create Docker network
sudo docker network create syncthing

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/syncthing/docker-compose.yml << EOF
services:
  syncthing:
    image: syncthing/syncthing:latest
    container_name: syncthing
    hostname: ${HOSTNAME}
    restart: always
    environment:
      - PUID=1000
      - PGID=1000
    networks:
      - syncthing
      - caddy
    volumes:
      - ${HOME}/syncthing:/var/syncthing
    ports:
      - 22000:22000/tcp
      - 22000:22000/udp
      - 21027:21027/udp

networks:
  syncthing:
    external: true
  caddy:
    external: true
EOF

################################################
##### Caddyfile
################################################

sudo tee -a /etc/selfhosted/caddy/Caddyfile << EOF

# Syncthing
syncthing.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy syncthing:8384 {
                header_up X-Real-IP {remote_host}
        }
}
EOF