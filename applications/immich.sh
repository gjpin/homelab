#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# References:
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
# https://github.com/immich-app/immich/blob/main/docker/.env.example
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create directory
sudo mkdir -p /etc/selfhosted/immich

# Create Docker network
sudo docker network create immich

# Create Docker volumes
sudo docker volume create immich
sudo docker volume create immich-postgres
sudo docker volume create immich-typesense
#sudo docker volume create immich-machine-learning

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/immich/docker-compose.yml << EOF
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-server
    entrypoint: ["/bin/sh", "./start-server.sh"]
    volumes:
      - immich:/usr/src/app/upload
    env_file:
      - config.env
    depends_on:
      - immich-redis
      - immich-postgres
      - typesense
    restart: always
    networks:
      - immich
      - caddy

  immich-microservices:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-microservices
    entrypoint: ["/bin/sh", "./start-microservices.sh"]
    volumes:
      - immich:/usr/src/app/upload
    env_file:
      - config.env
    depends_on:
      - immich-redis
      - immich-postgres
      - typesense
    restart: always
    networks:
      - immich

#  immich-machine-learning:
#    image: ghcr.io/immich-app/immich-machine-learning:release
#    container_name: immich-machine-learning
#    volumes:
#      - immich:/usr/src/app/upload
#      - immich-machine-learning:/cache
#    env_file:
#      - config.env
#    restart: always
#    networks:
#      - immich

  immich-web:
    image: ghcr.io/immich-app/immich-web:release
    container_name: immich-web
    entrypoint: ["/bin/sh", "./entrypoint.sh"]
    env_file:
      - config.env
    restart: always
    networks:
      - immich
      - caddy

  # immich-server is currently hardcoded to look for typesense (no env var as of today)
  typesense:
    container_name: immich-typesense
    image: typesense/typesense:0.24.0
    env_file:
      - config.env
    volumes:
      - immich-typesense:/data
    logging:
      driver: none
    restart: always
    networks:
      - immich

  immich-redis:
    container_name: immich-redis
    image: redis:alpine
    restart: always
    networks:
      - immich

  immich-postgres:
    container_name: immich-postgres
    image: postgres:15
    env_file:
      - config.env
    volumes:
      - immich-postgres:/var/lib/postgresql/data
    restart: always
    networks:
      - immich

  immich-proxy:
    container_name: immich-proxy
    image: ghcr.io/immich-app/immich-proxy:release
    logging:
      driver: none
    depends_on:
      - immich-server
    restart: always
    networks:
      - immich

volumes:
  immich:
    external: true
  immich-postgres:
    external: true
  immich-typesense:
    external: true
#  immich-machine-learning:
#    external: true

networks:
  immich:
    external: true
  caddy:
    external: true
EOF

################################################
##### Environment variables
################################################

DATABASE_PASSWORD=$(openssl rand -hex 48)

sudo tee /etc/selfhosted/immich/config.env << EOF
POSTGRES_PASSWORD=${DATABASE_PASSWORD}
POSTGRES_USER=immich
POSTGRES_DB=immich

DB_HOSTNAME=immich-postgres
DB_USERNAME=immich
DB_PASSWORD=${DATABASE_PASSWORD}
DB_DATABASE_NAME=immich
PG_DATA=/var/lib/postgresql/data

REDIS_HOSTNAME=immich-redis

TYPESENSE_API_KEY=$(openssl rand -hex 48)
TYPESENSE_DATA_DIR=/data

LOG_LEVEL=simple

JWT_SECRET=$(openssl rand -hex 48)

NODE_ENV=production

IMMICH_WEB_URL=http://immich-web:3000
IMMICH_SERVER_URL=http://immich-server:3001
#IMMICH_MACHINE_LEARNING_URL=http://immich-machine-learning:3003

MACHINE_LEARNING_ENABLED=false
EOF

################################################
##### Kernel configurations
################################################

# References:
# https://github.com/lucas-clemente/quic-go/wiki/UDP-Receive-Buffer-Size

sudo sysctl vm.overcommit_memory=1
sudo tee /etc/sysctl.d/99-overcommit-memory.conf << EOF
vm.overcommit_memory=1
EOF

################################################
##### Caddyfile
################################################

sudo tee -a /etc/selfhosted/caddy/Caddyfile << EOF

# Immich
photos.${BASE_DOMAIN} {
        import default-header

        encode gzip

        handle_path /api* {
                reverse_proxy immich-server:3001 {
                        header_up X-Real-IP {remote_host}
                }
        }

        reverse_proxy immich-web:3000 {
                header_up X-Real-IP {remote_host}
        }
}
EOF