#!/usr/bin/bash

# Create networks (Caddy belongs to all networks)
docker network create caddy
docker network create forgejo
docker network create firecrawl
docker network create homeassistant
docker network create immich
docker network create librechat
docker network create --internal radicale
docker network create searxng
docker network create supernote
docker network create syncthing
docker network create --internal vaultwarden

################################################
##### Env vars
################################################

# Store main env vars
cat <<EOF > "${HOME}/.bashrc.d/env"
export BASE_DOMAIN=${BASE_DOMAIN}
export DATA_PATH='${DATA_PATH}'
export BACKUP_PATH='${BACKUP_PATH}'

# Caddy
export CADDY_HASHED_PASSWORD='${CADDY_HASHED_PASSWORD}'
export CADDY_CLOUDFLARE_TOKEN='${CADDY_CLOUDFLARE_TOKEN}'

# Firecrawl
export FIRECRAWL_POSTGRES_PASSWORD='${FIRECRAWL_POSTGRES_PASSWORD}'
export FIRECRAWL_OPENAI_API_KEY='${FIRECRAWL_OPENAI_API_KEY}'

# Forgejo
export FORGEJO_DATABASE_PASSWORD='${FORGEJO_DATABASE_PASSWORD}'

# Home Assistant
export HOMEASSISTANT_MOSQUITTO_PASSWORD='${HOMEASSISTANT_MOSQUITTO_PASSWORD}'
export HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID='${HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID}'

# Immich
export IMMICH_DATABASE_PASSWORD='${IMMICH_DATABASE_PASSWORD}'
export IMMICH_JWT_SECRET='${IMMICH_JWT_SECRET}'

# LibreChat
export LIBRECHAT_CREDS_KEY='${LIBRECHAT_CREDS_KEY}'
export LIBRECHAT_CREDS_IV='${LIBRECHAT_CREDS_IV}'
export LIBRECHAT_MEILI_MASTER_KEY='${LIBRECHAT_MEILI_MASTER_KEY}'
export LIBRECHAT_JWT_SECRET='${LIBRECHAT_JWT_SECRET}'
export LIBRECHAT_JWT_REFRESH_SECRET='${LIBRECHAT_JWT_REFRESH_SECRET}'
export LIBRECHAT_POSTGRES_PASSWORD='${LIBRECHAT_POSTGRES_PASSWORD}'
export LIBRECHAT_OPENAI_API_KEY='${LIBRECHAT_OPENAI_API_KEY}'
export LIBRECHAT_DEEPSEEK_API_KEY='${LIBRECHAT_DEEPSEEK_API_KEY}'
export LIBRECHAT_OPENROUTER_API_KEY='${LIBRECHAT_OPENROUTER_API_KEY}'
export LIBRECHAT_JINA_API_KEY='${LIBRECHAT_JINA_API_KEY}'
export LIBRECHAT_FIRECRAWL_API_KEY='${LIBRECHAT_FIRECRAWL_API_KEY}'

# Radicale
export RADICALE_USER_PASSWORD='${RADICALE_USER_PASSWORD}'

# SearXNG
export SEARXNG_SECRET_KEY='${SEARXNG_SECRET_KEY}'

# Supernote
export SUPERNOTE_DATABASE_ROOT_PASSWORD='${SUPERNOTE_DATABASE_ROOT_PASSWORD}'
export SUPERNOTE_DATABASE_USER_PASSWORD='${SUPERNOTE_DATABASE_USER_PASSWORD}'
export SUPERNOTE_REDIS_PASSWORD='${SUPERNOTE_REDIS_PASSWORD}'

# Vaultwarden
export VAULTWARDEN_ADMIN_TOKEN='${VAULTWARDEN_ADMIN_TOKEN}'
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
envsubst < ./applications/caddy/Dockerfile | tee ${DATA_PATH}/caddy/docker/Dockerfile > /dev/null
envsubst < ./applications/caddy/docker-compose.yaml | tee ${DATA_PATH}/caddy/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/caddy/Caddyfile | tee ${DATA_PATH}/caddy/configs/Caddyfile > /dev/null

################################################
##### Firecrawl
################################################

# Create directories
mkdir -p ${DATA_PATH}/firecrawl/docker
mkdir -p ${DATA_PATH}/firecrawl/volumes/postgres

# Copy files to expected directories and expand variables
envsubst < ./applications/firecrawl/docker-compose.yaml | tee ${DATA_PATH}/firecrawl/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/firecrawl/config.env | tee ${DATA_PATH}/firecrawl/docker/config.env > /dev/null

################################################
##### Forgejo
################################################

# References:
# https://forgejo.org/docs/latest/admin/installation/docker/
# https://caddy.community/t/need-help-configuring-caddy-l4-for-git-ssh-access-on-domain/26405/2

# Create directories
mkdir -p ${DATA_PATH}/forgejo/docker
mkdir -p ${DATA_PATH}/forgejo/configs
mkdir -p ${DATA_PATH}/forgejo/volumes/{data,postgres}

sudo chown -R 1000:1000 ${DATA_PATH}/forgejo/configs
sudo chown -R 1000:1000 ${DATA_PATH}/forgejo/volumes/data

# Copy files to expected directories and expand variables
envsubst < ./applications/forgejo/docker-compose.yaml | tee ${DATA_PATH}/forgejo/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/forgejo/config.env | tee ${DATA_PATH}/forgejo/docker/config.env > /dev/null

################################################
##### Home Assistant
################################################

# Set required env var
export HOMEASSISTANT_TRUSTED_PROXY_SUBNET=$(docker network inspect homeassistant --format '{{(index .IPAM.Config 0).Subnet}}')

# Create directories
mkdir -p ${DATA_PATH}/homeassistant/docker
mkdir -p ${DATA_PATH}/homeassistant/volumes/zigbee2mqtt
mkdir -p ${DATA_PATH}/homeassistant/volumes/homeassistant/{www,custom_components}
mkdir -p ${DATA_PATH}/homeassistant/volumes/mosquitto/{config,data,log}

# Create mosquitto password file
if [ ! -f "${DATA_PATH}/homeassistant/volumes/mosquitto/config/pwfile" ]; then
touch ${DATA_PATH}/homeassistant/volumes/mosquitto/config/pwfile
docker run --rm -v ${DATA_PATH}/homeassistant/volumes/mosquitto/config/pwfile:/data/pwfile eclipse-mosquitto:2 \
    sh -c "mosquitto_passwd -b /data/pwfile ha ${HOMEASSISTANT_MOSQUITTO_PASSWORD}"
fi

# Install HACS
# Configure HACS:
# https://hacs.xyz/docs/use/configuration/basic/
if [ ! -d "${DATA_PATH}/homeassistant/volumes/homeassistant/custom_components" ]; then
  mkdir -p "${DATA_PATH}/homeassistant/volumes/homeassistant/custom_components/hacs"
  wget -P "${DATA_PATH}/homeassistant/volumes/homeassistant/custom_components" https://github.com/hacs/integration/releases/latest/download/hacs.zip
  unzip "${DATA_PATH}/homeassistant/volumes/homeassistant/custom_components/hacs.zip" -d "${DATA_PATH}/homeassistant/volumes/homeassistant/custom_components/hacs" >/dev/null 2>&1
  rm -f "${DATA_PATH}/homeassistant/volumes/homeassistant/custom_components/hacs.zip"
fi

# Install bambulab custom resources
# https://www.wolfwithsword.com/bambulab-home-assistant-dashboard/
if [ ! -d "${DATA_PATH}/homeassistant/volumes/homeassistant/www/media/bambuprinter" ]; then
  wget -P "${DATA_PATH}/homeassistant/volumes/homeassistant" https://github.com/WolfwithSword/Bambu-HomeAssistant-Flows/releases/download/nightly/bambu-ha-media-files.zip
  unzip "${DATA_PATH}/homeassistant/volumes/homeassistant/bambu-ha-media-files.zip"
  rm -f "${DATA_PATH}/homeassistant/volumes/homeassistant/bambu-ha-media-files.zip"
fi

# Add HA cards
# Enable them: Settings -> Dashboards -> 3 dots -> Resources -> Add resource
# /local/mini-graph-card-bundle.js
# /local/timer-bar-card.js
if [ ! -d "${DATA_PATH}/homeassistant/volumes/homeassistant/www/community/mini-graph-card" ]; then
  wget -P "${DATA_PATH}/homeassistant/volumes/homeassistant/www" https://github.com/kalkih/mini-graph-card/releases/latest/download/mini-graph-card-bundle.js
  wget -P "${DATA_PATH}/homeassistant/volumes/homeassistant/www" https://github.com/rianadon/timer-bar-card/releases/latest/download/timer-bar-card.js
fi

# Copy files to expected directories and expand variables
envsubst < ./applications/homeassistant/docker-compose.yaml | tee ${DATA_PATH}/homeassistant/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/homeassistant/homeassistant.yaml | tee ${DATA_PATH}/homeassistant/volumes/homeassistant/configuration.yaml > /dev/null
envsubst < ./applications/homeassistant/automations.yaml | tee ${DATA_PATH}/homeassistant/volumes/homeassistant/automations.yaml > /dev/null
envsubst < ./applications/homeassistant/zigbee2mqtt.yaml | tee ${DATA_PATH}/homeassistant/volumes/zigbee2mqtt/configuration.yaml > /dev/null

if [ ! -f "${DATA_PATH}/homeassistant/volumes/mosquitto/config/mosquitto.conf" ]; then
  envsubst < ./applications/homeassistant/mosquitto.conf | tee ${DATA_PATH}/homeassistant/volumes/mosquitto/config/mosquitto.conf > /dev/null
fi

################################################
##### Immich
################################################

# References:
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yaml
# https://github.com/immich-app/immich/blob/main/docker/example.env
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create directories
mkdir -p ${DATA_PATH}/immich/docker
mkdir -p ${DATA_PATH}/immich/volumes/{immich,postgres,machine-learning}

# Copy files to expected directories and expand variables
envsubst < ./applications/immich/docker-compose.yaml | tee ${DATA_PATH}/immich/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/immich/config.env | tee ${DATA_PATH}/immich/docker/config.env > /dev/null

################################################
##### LibreChat
################################################

# References:
# https://github.com/danny-avila/LibreChat/blob/v0.8.5/.env.example
# https://github.com/danny-avila/LibreChat/blob/v0.8.5/librechat.example.yaml
# https://www.librechat.ai/docs/configuration/librechat_yaml

# Create directories
mkdir -p ${DATA_PATH}/librechat/docker
mkdir -p ${DATA_PATH}/librechat/volumes/librechat/{images,logs}
mkdir -p ${DATA_PATH}/librechat/volumes/{mongodb,meilisearch,pgvector}

# Copy files to expected directories and expand variables
envsubst < ./applications/librechat/config.env | tee ${DATA_PATH}/librechat/docker/config.env > /dev/null
envsubst < ./applications/librechat/docker-compose.yaml | tee ${DATA_PATH}/librechat/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/librechat/librechat.yaml | tee ${DATA_PATH}/librechat/configs/librechat.yaml > /dev/null

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
envsubst < ./applications/radicale/docker-compose.yaml | tee ${DATA_PATH}/radicale/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/radicale/config | tee ${DATA_PATH}/radicale/configs/config > /dev/null
envsubst < ./applications/radicale/users | tee ${DATA_PATH}/radicale/configs/users > /dev/null

################################################
##### SearXNG
################################################

# References:
# https://docs.searxng.org/admin/settings/index.html

# Create directories
mkdir -p ${DATA_PATH}/searxng/docker
mkdir -p ${DATA_PATH}/searxng/configs
mkdir -p ${DATA_PATH}/searxng/volumes/data
mkdir -p ${DATA_PATH}/searxng/volumes/valkey

# Copy files to expected directories and expand variables
envsubst < ./applications/searxng/docker-compose.yaml | tee ${DATA_PATH}/searxng/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/searxng/settings.yml | tee ${DATA_PATH}/searxng/configs/settings.yml > /dev/null

################################################
##### Supernote
################################################

# References:
# https://support.supernote.com/setting-up-your-own-supernote-private-cloud-beta
# https://ib.supernote.com/private-cloud/Supernote-Private-Cloud-Manual-Deployment-Method-Using-Docker-Containers.pdf
# https://supernote-privatecloud.supernote.com/cloud/supernotedb.sql

# Create directories
mkdir -p ${DATA_PATH}/supernote/docker
mkdir -p ${DATA_PATH}/supernote/configs
mkdir -p ${DATA_PATH}/supernote/volumes/{mariadb,redis,resources}
mkdir -p ${DATA_PATH}/supernote/volumes/supernote/{data,recycle,logs-cloud,logs-app,logs-web,convert}

# Copy files to expected directories and expand variables
cp applications/supernote/supernotedb.sql ${DATA_PATH}/supernote/volumes/resources
envsubst '$DATA_PATH' < ./applications/supernote/docker-compose.yaml | tee ${DATA_PATH}/supernote/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/supernote/config.env | tee ${DATA_PATH}/supernote/docker/config.env > /dev/null

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
envsubst < ./applications/syncthing/docker-compose.yaml | tee ${DATA_PATH}/syncthing/docker/docker-compose.yaml > /dev/null

################################################
##### Vaultwarden
################################################

# Create directories
mkdir -p ${DATA_PATH}/vaultwarden/docker
mkdir -p ${DATA_PATH}/vaultwarden/configs
mkdir -p ${DATA_PATH}/vaultwarden/volumes/vaultwarden

# Copy files to expected directories and expand variables
envsubst < ./applications/vaultwarden/docker-compose.yaml | tee ${DATA_PATH}/vaultwarden/docker/docker-compose.yaml > /dev/null
envsubst < ./applications/vaultwarden/config.env | tee ${DATA_PATH}/vaultwarden/docker/config.env > /dev/null