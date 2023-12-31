#!/usr/bin/bash

# References:
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
# https://github.com/immich-app/immich/blob/main/docker/example.env
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create Docker network
sudo docker network create --internal immich

# Create directories
mkdir -p ${DATA_PATH}/immich/docker
mkdir -p ${DATA_PATH}/immich/configs
mkdir -p ${DATA_PATH}/immich/volumes/{immich,postgres,machine-learning}

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/immich/docker/docker-compose.yml << EOF
services:
  immich-server:
    container_name: immich-server
    image: ghcr.io/immich-app/immich-server:release
    command: [ "start.sh", "immich" ]
    volumes:
      - ${DATA_PATH}/immich/volumes/immich:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - config.env
    depends_on:
      - immich-redis
      - immich-postgres
    restart: always
    networks:
      - immich

  immich-microservices:
    container_name: immich-microservices
    image: ghcr.io/immich-app/immich-server:release
    command: [ "start.sh", "microservices" ]
    volumes:
      - ${DATA_PATH}/immich/volumes/immich:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - config.env
    depends_on:
      - immich-redis
      - immich-postgres
    restart: always
    networks:
      - immich

  immich-machine-learning:
    container_name: immich-machine-learning
    image: ghcr.io/immich-app/immich-machine-learning:release
    volumes:
      - ${DATA_PATH}/immich/volumes/machine-learning:/cache
    env_file:
      - config.env
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
    image: tensorchord/pgvecto-rs:pg15-v0.1.11
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/immich/volumes/postgres:/var/lib/postgresql/data
    restart: always
    networks:
      - immich

networks:
  immich:
    external: true
EOF

################################################
##### Environment variables
################################################

sudo tee ${DATA_PATH}/immich/docker/config.env << EOF
POSTGRES_PASSWORD=${IMMICH_DATABASE_PASSWORD}
POSTGRES_USER=immich
POSTGRES_DB=immich

DB_HOSTNAME=immich-postgres
DB_USERNAME=immich
DB_PASSWORD=${IMMICH_DATABASE_PASSWORD}
DB_DATABASE_NAME=immich
PG_DATA=/var/lib/postgresql/data

REDIS_HOSTNAME=immich-redis

TYPESENSE_ENABLED=false

LOG_LEVEL=warn

JWT_SECRET=${IMMICH_JWT_SECRET}

NODE_ENV=production

IMMICH_VERSION=release
IMMICH_WEB_URL=http://immich-web:3000
IMMICH_SERVER_URL=http://immich-server:3001

MACHINE_LEARNING_ENABLED=false
DISABLE_REVERSE_GEOCODING=true
EOF