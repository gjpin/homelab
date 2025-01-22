#!/usr/bin/bash

# References:
# Update pgvecto.rs: https://docs.pgvecto.rs/admin/upgrading.html
  # docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d immich-postgres
  # docker exec -ti immich-postgres bash
  # psql postgresql://immich:${IMMICH_DATABASE_PASSWORD}@immich-postgres:5432/immich
  # ... follow the rest
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
# https://github.com/immich-app/immich/blob/main/docker/example.env
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create Docker network
docker network create --internal immich

# Create directories
mkdir -p ${DATA_PATH}/immich/docker
mkdir -p ${DATA_PATH}/immich/volumes/{immich,postgres}

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/immich/docker/docker-compose.yml << EOF
services:
  immich-server:
    container_name: immich-server
    image: ghcr.io/immich-app/immich-server:v1.124.2
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

  immich-redis:
    container_name: immich-redis
    image: docker.io/redis:7.4.2-alpine
    healthcheck:
      test: redis-cli ping || exit 1
    restart: always
    networks:
      - immich

  immich-postgres:
    container_name: immich-postgres
    image: docker.io/tensorchord/pgvecto-rs:pg15-v0.3.0
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/immich/volumes/postgres:/var/lib/postgresql/data
    healthcheck:
      test: pg_isready --dbname='immich' --username='immich' || exit 1; Chksum="$$(psql --dbname='immich' --username='immich' --tuples-only --no-align --command='SELECT COALESCE(SUM(checksum_failures), 0) FROM pg_stat_database')"; echo "checksum failure count is $$Chksum"; [ "$$Chksum" = '0' ] || exit 1
      interval: 5m
      start_interval: 30s
      start_period: 5m
    command: ["postgres", "-c", "shared_preload_libraries=vectors.so", "-c", 'search_path="$$user", public, vectors', "-c", "logging_collector=on", "-c", "max_wal_size=2GB", "-c", "shared_buffers=512MB", "-c", "wal_compression=on"]
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
POSTGRES_INITDB_ARGS="--data-checksums"

DB_HOSTNAME=immich-postgres
DB_USERNAME=immich
DB_PASSWORD=${IMMICH_DATABASE_PASSWORD}
DB_DATABASE_NAME=immich

REDIS_HOSTNAME=immich-redis

UPLOAD_LOCATION=./library
DB_DATA_LOCATION=./postgres

MACHINE_LEARNING_ENABLED=false
EOF