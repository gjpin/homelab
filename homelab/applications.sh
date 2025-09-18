#!/usr/bin/bash

# Create networks (Caddy belongs to all networks)
docker network create caddy
docker network create gitea
docker network create homeassistant
docker network create --internal immich
docker network create librechat
docker network create --internal obsidian
docker network create --internal radicale
docker network create supabase
docker network create syncthing
docker network create --internal vaultwarden

################################################
##### Env vars
################################################

# Ente
export ENTE_DATABASE_PASSWORD=$(openssl rand -hex 48)
export ENTE_KEY_ENCRYPTION=$(openssl rand -base64 32)
export ENTE_KEY_HASH=$(openssl rand -base64 64 | tr -d '\n')
export ENTE_JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')

# Store main env vars
cat <<EOF >> "${HOME}/.bashrc.d/env"
export BASE_DOMAIN=${BASE_DOMAIN}
export DATA_PATH='${DATA_PATH}'
export BACKUP_PATH='${BACKUP_PATH}'

# Caddy
export CADDY_HASHED_PASSWORD='${CADDY_HASHED_PASSWORD}'
export CADDY_CLOUDFLARE_TOKEN='${CADDY_CLOUDFLARE_TOKEN}'

# Home Assistant
export HOMEASSISTANT_MOSQUITTO_PASSWORD='${HOMEASSISTANT_MOSQUITTO_PASSWORD}'
export HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID='${HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID}'

# Immich
export IMMICH_DATABASE_PASSWORD='${IMMICH_DATABASE_PASSWORD}'
export IMMICH_JWT_SECRET='${IMMICH_JWT_SECRET}'

# Obsidian
export OBSIDIAN_COUCHDB_PASSWORD='${OBSIDIAN_COUCHDB_PASSWORD}'

# Radicale
export RADICALE_USER_PASSWORD='${RADICALE_USER_PASSWORD}'

# Vaultwarden
export VAULTWARDEN_ADMIN_TOKEN='${VAULTWARDEN_ADMIN_TOKEN}'

# Gitea
export GITEA_DATABASE_PASSWORD='${GITEA_DATABASE_PASSWORD}'

# LibreChat
export LIBRECHAT_DOMAIN_CLIENT='https://chat.${BASE_DOMAIN}'
export LIBRECHAT_DOMAIN_SERVER='https://chat.${BASE_DOMAIN}'
export LIBRECHAT_CREDS_KEY='${LIBRECHAT_CREDS_KEY}'
export LIBRECHAT_CREDS_IV='${LIBRECHAT_CREDS_IV}'
export LIBRECHAT_MEILI_MASTER_KEY='${LIBRECHAT_MEILI_MASTER_KEY}'
export LIBRECHAT_JWT_SECRET='${LIBRECHAT_JWT_SECRET}'
export LIBRECHAT_JWT_REFRESH_SECRET='${LIBRECHAT_JWT_REFRESH_SECRET}'
export LIBRECHAT_POSTGRES_PASSWORD='${LIBRECHAT_POSTGRES_PASSWORD}'
export LIBRECHAT_RAG_OPENAI_API_KEY='${LIBRECHAT_RAG_OPENAI_API_KEY}'
export LIBRECHAT_OPENAI_API_KEY='${LIBRECHAT_OPENAI_API_KEY}'
export LIBRECHAT_GROQ_API_KEY='${LIBRECHAT_GROQ_API_KEY}'
export LIBRECHAT_MISTRAL_API_KEY='${LIBRECHAT_MISTRAL_API_KEY}'
export LIBRECHAT_DEEPSEEK_API_KEY='${LIBRECHAT_DEEPSEEK_API_KEY}'

# Supabase
export SUPABASE_LOGFLARE_API_KEY='${SUPABASE_LOGFLARE_API_KEY}'
export SUPABASE_POSTGRES_PASSWORD='${SUPABASE_POSTGRES_PASSWORD}'
export SUPABASE_POSTGRES_PORT='${SUPABASE_POSTGRES_PORT}'
export SUPABASE_POSTGRES_DB='${SUPABASE_POSTGRES_DB}'
export SUPABASE_POSTGRES_HOST='${SUPABASE_POSTGRES_HOST}'
export SUPABASE_JWT_SECRET='${SUPABASE_JWT_SECRET}'
export SUPABASE_ANON_KEY='${SUPABASE_ANON_KEY}'
export SUPABASE_SERVICE_KEY='${SUPABASE_SERVICE_KEY}'
export SUPABASE_DEFAULT_ORGANIZATION_NAME='${SUPABASE_DEFAULT_ORGANIZATION_NAME}'
export SUPABASE_DEFAULT_PROJECT_NAME='${SUPABASE_DEFAULT_PROJECT_NAME}'
export SUPABASE_OPENAI_API_KEY='${SUPABASE_OPENAI_API_KEY}'
export SUPABASE_PUBLIC_URL='https://supabase.${BASE_DOMAIN}'
export SUPABASE_KONG_DASHBOARD_USERNAME='${SUPABASE_KONG_DASHBOARD_USERNAME}'
export SUPABASE_KONG_DASHBOARD_PASSWORD='${SUPABASE_KONG_DASHBOARD_PASSWORD}'
export SUPABASE_API_EXTERNAL_URL='https://supabase.${BASE_DOMAIN}'
export SUPABASE_SITE_URL='https://supabase.${BASE_DOMAIN}'
export SUPABASE_ADDITIONAL_REDIRECT_URLS=
export SUPABASE_SECRET_KEY_BASE='${SUPABASE_SECRET_KEY_BASE}'
export SUPABASE_VAULT_ENC_KEY='${SUPABASE_VAULT_ENC_KEY}'
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
envsubst < ./applications/caddy/docker-compose.yaml | tee ${DATA_PATH}/caddy/docker/docker-compose.yml > /dev/null
envsubst < ./applications/caddy/Caddyfile | tee ${DATA_PATH}/caddy/configs/Caddyfile > /dev/null

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
envsubst < ./applications/homeassistant/docker-compose.yaml | tee ${DATA_PATH}/homeassistant/docker/docker-compose.yml > /dev/null
envsubst < ./applications/homeassistant/homeassistant.yaml | tee ${DATA_PATH}/homeassistant/volumes/homeassistant/configuration.yaml > /dev/null
envsubst < ./applications/homeassistant/zigbee2mqtt.yaml | tee ${DATA_PATH}/homeassistant/volumes/zigbee2mqtt/configuration.yaml > /dev/null

if [ ! -f "${DATA_PATH}/homeassistant/volumes/mosquitto/config/mosquitto.conf" ]; then
  envsubst < ./applications/homeassistant/mosquitto.conf | tee ${DATA_PATH}/homeassistant/volumes/mosquitto/config/mosquitto.conf > /dev/null
fi

################################################
##### Immich
################################################

# References:
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
# https://github.com/immich-app/immich/blob/main/docker/example.env
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create directories
mkdir -p ${DATA_PATH}/immich/docker
mkdir -p ${DATA_PATH}/immich/volumes/{immich,postgres}

# Copy files to expected directories and expand variables
envsubst < ./applications/immich/docker-compose.yaml | tee ${DATA_PATH}/immich/docker/docker-compose.yml > /dev/null
envsubst < ./applications/immich/config.env | tee ${DATA_PATH}/immich/docker/config.env > /dev/null

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
envsubst < ./applications/librechat/docker-compose.yaml $| tee ${DATA_PATH}/librechat/docker/docker-compose.yml > /dev/null
envsubst < ./applications/librechat/config.env | tee ${DATA_PATH}/librechat/docker/config.env > /dev/null
envsubst < ./applications/librechat/librechat.yaml | tee ${DATA_PATH}/librechat/configs/librechat.yaml > /dev/null

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

################################################
##### Supabase
################################################

# Create directories
mkdir -p ${DATA_PATH}/supabase/docker/volumes
mkdir -p ${DATA_PATH}/supabase/configs
mkdir -p ${DATA_PATH}/supabase/volumes

# Copy files to expected directories and expand variables
sudo cp -R ./applications/supabase/volumes/* ${DATA_PATH}/supabase/docker/volumes/
envsubst < ./applications/supabase/volumes/api/kong.yml | tee ${DATA_PATH}/supabase/volumes/api/kong.yml > /dev/null
envsubst < ./applications/supabase/docker-compose.yaml | tee ${DATA_PATH}/supabase/docker/docker-compose.yml > /dev/null
envsubst < ./applications/supabase/config.env | tee ${DATA_PATH}/supabase/docker/config.env > /dev/null

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