#!/usr/bin/bash

# Create networks (Caddy belongs to all networks)
sudo docker network create caddy
sudo docker network create gitea
sudo docker network create --internal immich
sudo docker network create librechat
sudo docker network create --internal obsidian
sudo docker network create --internal radicale
sudo docker network create supabase
sudo docker network create syncthing
sudo docker network create --internal vaultwarden

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

# Install systemd service
envsubst < ./applications/caddy/caddy.service | sudo tee /etc/systemd/system/caddy.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable caddy.service

################################################
##### Supabase
################################################

# Create directories
mkdir -p ${DATA_PATH}/supabase/docker
mkdir -p ${DATA_PATH}/supabase/configs
mkdir -p ${DATA_PATH}/supabase/volumes

# Copy files to expected directories and expand variables
cp -R ./applications/supabase/volumes/* ${DATA_PATH}/supabase/volumes/
envsubst < ./applications/supabase/volumes/api/kong.yml | tee ${DATA_PATH}/supabase/volumes/api/kong.yml > /dev/null
envsubst < ./applications/supabase/docker-compose.yaml | tee ${DATA_PATH}/supabase/docker/docker-compose.yml > /dev/null
envsubst < ./applications/supabase/config.env | tee ${DATA_PATH}/supabase/docker/config.env > /dev/null

# Install systemd service
envsubst < ./applications/supabase/supabase.service | sudo tee /etc/systemd/system/supabase.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable supabase.service

################################################
##### Gitea
################################################

# References:
# https://docs.gitea.com/installation/install-with-docker-rootless
# https://caddy.community/t/need-help-configuring-caddy-l4-for-git-ssh-access-on-domain/26405/2

# Create directories
mkdir -p ${DATA_PATH}/gitea/docker
mkdir -p ${DATA_PATH}/gitea/configs
mkdir -p ${DATA_PATH}/gitea/volumes/{gitea,postgres}

sudo chown -R 1000:1000 ${DATA_PATH}/gitea/configs
sudo chown -R 1000:1000 ${DATA_PATH}/gitea/volumes/gitea

# Copy files to expected directories and expand variables
envsubst < ./applications/gitea/docker-compose.yaml | tee ${DATA_PATH}/gitea/docker/docker-compose.yml > /dev/null
envsubst < ./applications/gitea/config.env | tee ${DATA_PATH}/gitea/docker/config.env > /dev/null

# Install systemd service
envsubst < ./applications/gitea/gitea.service | sudo tee /etc/systemd/system/gitea.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable gitea.service

################################################
##### Immich
################################################

# References:
# Update pgvecto.rs: https://docs.pgvecto.rs/admin/upgrading.html
  # docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d immich-postgres
  # docker exec -ti immich-postgres bash
  # psql postgresql://immich:${IMMICH_DATABASE_PASSWORD}@immich-postgres:5432/immich
  # ... follow the rest
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
# https://github.com/immich-app/immich/blob/main/docker/example.env
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create directories
mkdir -p ${DATA_PATH}/immich/docker
mkdir -p ${DATA_PATH}/immich/volumes/{immich,postgres}

# Copy files to expected directories and expand variables
envsubst < ./applications/immich/docker-compose.yaml | tee ${DATA_PATH}/immich/docker/docker-compose.yml > /dev/null
envsubst < ./applications/immich/config.env | tee ${DATA_PATH}/immich/docker/config.env > /dev/null

# Install systemd service
envsubst < ./applications/immich/immich.service | sudo tee /etc/systemd/system/immich.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable immich.service

################################################
##### LibreChat
################################################

# References:
# https://github.com/danny-avila/LibreChat/blob/main/docker-compose.yml
# https://www.librechat.ai/docs/local/docker
# https://github.com/themattman/mongodb-raspberrypi-docker
# https://github.com/gjpin/mongodb-raspberrypi-docker
# https://github.com/danny-avila/LibreChat/blob/main/.env.example
# https://www.librechat.ai/docs/configuration/dotenv

# Create directories
mkdir -p ${DATA_PATH}/librechat/docker
mkdir -p ${DATA_PATH}/librechat/configs
mkdir -p ${DATA_PATH}/librechat/volumes/librechat/{logs,images}
mkdir -p ${DATA_PATH}/librechat/volumes/{mongodb,pgvector,meilisearch}

# Fix permissions
sudo chown -R 1000:1000 ${DATA_PATH}/librechat/configs
sudo chown -R 1000:1000 ${DATA_PATH}/librechat/volumes

# Copy files to expected directories and expand variables
envsubst < ./applications/librechat/docker-compose.yaml $| tee {DATA_PATH}/librechat/docker/docker-compose.yml > /dev/null
envsubst < ./applications/librechat/config.env | tee ${DATA_PATH}/librechat/docker/config.env > /dev/null
envsubst < ./applications/librechat/librechat.yaml | tee ${DATA_PATH}/librechat/configs/librechat.yaml > /dev/null

# Install systemd service
envsubst < ./applications/librechat/librechat.service | sudo tee /etc/systemd/system/librechat.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable librechat.service

################################################
##### Obsidian
################################################

# References:
# https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/setup_own_server.md

# Create directories
mkdir -p ${DATA_PATH}/obsidian/docker
mkdir -p ${DATA_PATH}/obsidian/configs
mkdir -p ${DATA_PATH}/obsidian/volumes/obsidian

# Copy files to expected directories and expand variables
envsubst < ./applications/obsidian/docker-compose.yaml | tee ${DATA_PATH}/obsidian/docker/docker-compose.yml > /dev/null
envsubst < ./applications/obsidian/config.env | tee ${DATA_PATH}/obsidian/docker/config.env > /dev/null
envsubst < ./applications/obsidian/local.ini | tee ${DATA_PATH}/obsidian/configs/local.ini > /dev/null

# Install systemd service
envsubst < ./applications/obsidian/obsidian.service | sudo tee /etc/systemd/system/obsidian.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable obsidian.service

################################################
##### Radicale
################################################

# References:
# https://radicale.org/v3.html#basic-configuration
# https://caddy.community/t/radicale-reverse-proxy-caddy-2-0/8580/5

# Create directories
mkdir -p ${DATA_PATH}/radicale/docker
mkdir -p ${DATA_PATH}/radicale/configs
mkdir -p ${DATA_PATH}/radicale/volumes/radicale

# Copy files to expected directories and expand variables
envsubst < ./applications/radicale/Dockerfile | tee ${DATA_PATH}/radicale/docker/Dockerfile > /dev/null
envsubst < ./applications/radicale/docker-compose.yaml | tee ${DATA_PATH}/radicale/docker/docker-compose.yml > /dev/null
envsubst < ./applications/radicale/config | tee ${DATA_PATH}/radicale/configs/config > /dev/null
envsubst < ./applications/radicale/users | tee ${DATA_PATH}/radicale/configs/users > /dev/null

# Install systemd service
envsubst < ./applications/radicale/radicale.service | sudo tee /etc/systemd/system/radicale.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable radicale.service

################################################
##### Syncthing
################################################

# References:
# https://github.com/syncthing/syncthing/blob/main/README-Docker.md

# Create directories
mkdir -p ${DATA_PATH}/syncthing/docker
mkdir -p ${DATA_PATH}/syncthing/configs
mkdir -p ${DATA_PATH}/syncthing/volumes/syncthing

# Copy files to expected directories and expand variables
envsubst < ./applications/syncthing/docker-compose.yaml | tee ${DATA_PATH}/syncthing/docker/docker-compose.yml > /dev/null

# Install systemd service
envsubst < ./applications/syncthing/syncthing.service | sudo tee /etc/systemd/system/syncthing.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable syncthing.service

################################################
##### Vaultwarden
################################################

# Create directories
mkdir -p ${DATA_PATH}/vaultwarden/docker
mkdir -p ${DATA_PATH}/vaultwarden/configs
mkdir -p ${DATA_PATH}/vaultwarden/volumes/vaultwarden

# Copy files to expected directories and expand variables
envsubst < ./applications/vaultwarden/docker-compose.yaml | tee ${DATA_PATH}/vaultwarden/docker/docker-compose.yml > /dev/null
envsubst < ./applications/vaultwarden/config.env | tee ${DATA_PATH}/vaultwarden/docker/config.env > /dev/null

# Install systemd service
envsubst < ./applications/vaultwarden/vaultwarden.service | sudo tee /etc/systemd/system/vaultwarden.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable vaultwarden.service