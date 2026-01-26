#!/usr/bin/bash

# Create networks (Caddy belongs to all networks)
docker network create caddy
docker network create forgejo
docker network create homeassistant
docker network create immich
docker network create --internal radicale
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

# Forgejo
export FORGEJO_DATABASE_PASSWORD='${FORGEJO_DATABASE_PASSWORD}'

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
envsubst < ./applications/caddy/docker-compose.yaml | tee ${DATA_PATH}/caddy/docker/docker-compose.yml > /dev/null
envsubst < ./applications/caddy/Caddyfile | tee ${DATA_PATH}/caddy/configs/Caddyfile > /dev/null

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
envsubst < ./applications/forgejo/docker-compose.yaml | tee ${DATA_PATH}/forgejo/docker/docker-compose.yml > /dev/null
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
envsubst < ./applications/homeassistant/docker-compose.yaml | tee ${DATA_PATH}/homeassistant/docker/docker-compose.yml > /dev/null
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
# https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
# https://github.com/immich-app/immich/blob/main/docker/example.env
# https://github.com/immich-app/immich/blob/main/nginx/nginx.conf

# Create directories
mkdir -p ${DATA_PATH}/immich/docker
mkdir -p ${DATA_PATH}/immich/volumes/{immich,postgres,machine-learning}

# Copy files to expected directories and expand variables
envsubst < ./applications/immich/docker-compose.yaml | tee ${DATA_PATH}/immich/docker/docker-compose.yml > /dev/null
envsubst < ./applications/immich/config.env | tee ${DATA_PATH}/immich/docker/config.env > /dev/null

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
cp applications/supernote/supernotedb.sql ${DATA_PATH}/supernote/volumes/resources/supernotedb.sql
envsubst < ./applications/supernote/docker-compose.yaml | tee ${DATA_PATH}/supernote/docker/docker-compose.yml > /dev/null
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