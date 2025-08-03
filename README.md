# Services
| Name | URL | Description | Access to internet |
| --- | --- | --- | --- |
| [Caddy](https://github.com/caddyserver/caddy) | bookmarks.${BASE_DOMAIN} | Web server and reverse proxy | Yes |
| [Immich](https://github.com/immich-app/immich) | photos.${BASE_DOMAIN} | Photo and video backup solution | No |
| [Obsidian LiveSync](https://github.com/vrtmrz/obsidian-livesync) | obsidian.${BASE_DOMAIN} | Community-implemented synchronization plugin | No |
| [Pi-hole](https://github.com/pi-hole/pi-hole) | pihole.${BASE_DOMAIN} | DNS server | Yes |
| [Technitium](https://github.com/TechnitiumSoftware/DnsServer) | technitium.${BASE_DOMAIN} | DNS server | Yes |
| [Radicale](https://github.com/Kozea/Radicale) | contacts.${BASE_DOMAIN} | CardDAV (contact) server | No |
| [Syncthing](https://github.com/syncthing/syncthing) | syncthing.${BASE_DOMAIN} | Continuous File Synchronization | Yes |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | vault.${BASE_DOMAIN} | Unofficial Bitwarden compatible server | No |
| [Gitea](https://github.com/go-gitea/gitea) | git.${BASE_DOMAIN} | Git server / DevOps platform | Yes |
| [LibreChat](https://github.com/danny-avila/LibreChat) | chat.${BASE_DOMAIN} | Enhanced ChatGPT Clone | Yes |
| [Home Assistant](https://github.com/home-assistant/core) | home.${BASE_DOMAIN} | Home automation | Yes |
| [Zigbee2MQTT](https://github.com/Koenkk/zigbee2mqtt) | home-zigbee.${BASE_DOMAIN} | Zigbee to MQTT bridge | Yes |
| [Ente](https://github.com/ente-io/ente) | 2fa.${BASE_DOMAIN} | End-to-end encrypted cloud for photos, videos and 2FA secrets. Only 2FA is configured | no |

# Getting started
0. Copy SSH public key to PC. If it's on a USB, mount it and copy to ${HOME}/.ssh:
```bash
sudo udisksctl mount -b /dev/sda
```
1. Set env vars (see below)
2. Setup machine and applications
```bash
git clone --depth 1 https://github.com/gjpin/homelab
cd homelab
./setup.sh
./applications.sh # or selectively go through applications.sh
```
3. Configure and enable WireGuard `sudo nmcli con import type wireguard file /etc/wireguard/wg0.conf`
4. Create DNS entries in Cloudflare, pointing to Wireguard's internal address
5. Reboot
6. Create borg repo (if not created yet): `borg init --encryption=none /backup/containers`

# Env vars
## DNS server
```bash
# Base
export BASE_DOMAIN=domain.com
export DATA_PATH=$HOME/containers

# Caddy
export CADDY_PASSWORD=$(openssl rand -hex 48)
export CADDY_HASHED_PASSWORD=$(docker run caddy:2-alpine caddy hash-password --plaintext ${CADDY_PASSWORD})
export CADDY_CLOUDFLARE_TOKEN=taken from Cloudflare

# Pi-Hole
export PIHOLE_WEBPASSWORD=$(openssl rand -hex 48)

# Technitium
export TECHNITIUM_ADMIN_PASSWORD=$(openssl rand -hex 48)
```

## Homelab
```bash
# Base
export BASE_DOMAIN=domain.com
export DATA_PATH=/data/containers
export BACKUP_PATH=/backup/containers

# Caddy
export CADDY_PASSWORD=$(openssl rand -hex 48)
export CADDY_HASHED_PASSWORD=$(docker run caddy:2-alpine caddy hash-password --plaintext ${CADDY_PASSWORD})
export CADDY_CLOUDFLARE_TOKEN=taken from Cloudflare

# Home Assistant
export HOMEASSISTANT_MOSQUITTO_PASSWORD=
export HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID= # check devices under /dev/serial/by-id

# Immich
export IMMICH_DATABASE_PASSWORD=$(openssl rand -hex 48)
export IMMICH_JWT_SECRET=$(openssl rand -hex 48)

# Obsidian
export OBSIDIAN_COUCHDB_PASSWORD=$(openssl rand -hex 48)

# Radicale
export RADICALE_PASSWORD=$(openssl rand -hex 48)
export RADICALE_USER_PASSWORD=$(htpasswd -n -b admin ${RADICALE_PASSWORD})

# Vaultwarden
export VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -hex 48)

# Gitea
export GITEA_DATABASE_PASSWORD=$(openssl rand -hex 48)

# LibreChat
export LIBRECHAT_DOMAIN_CLIENT=https://chat.${BASE_DOMAIN}
export LIBRECHAT_DOMAIN_SERVER=https://chat.${BASE_DOMAIN}
export LIBRECHAT_CREDS_KEY=$(openssl rand -hex 32)
export LIBRECHAT_CREDS_IV=$(openssl rand -hex 16)
export LIBRECHAT_MEILI_MASTER_KEY=$(openssl rand -hex 16)
export LIBRECHAT_JWT_SECRET=$(openssl rand -hex 32)
export LIBRECHAT_JWT_REFRESH_SECRET=$(openssl rand -hex 32)
export LIBRECHAT_POSTGRES_PASSWORD=$(openssl rand -hex 32)
export LIBRECHAT_RAG_OPENAI_API_KEY=
export LIBRECHAT_OPENAI_API_KEY=
export LIBRECHAT_GROQ_API_KEY=
export LIBRECHAT_MISTRAL_API_KEY=
export LIBRECHAT_DEEPSEEK_API_KEY=

# Supabase
export SUPABASE_LOGFLARE_API_KEY=
export SUPABASE_POSTGRES_PASSWORD=
export SUPABASE_POSTGRES_PORT="5432"
export SUPABASE_POSTGRES_DB="postgres"
export SUPABASE_POSTGRES_HOST="supabase-db"
export SUPABASE_JWT_SECRET=
export SUPABASE_ANON_KEY=
export SUPABASE_SERVICE_KEY=
export SUPABASE_DEFAULT_ORGANIZATION_NAME=
export SUPABASE_DEFAULT_PROJECT_NAME="Main"
export SUPABASE_OPENAI_API_KEY=
export SUPABASE_PUBLIC_URL="https://supabase.${BASE_DOMAIN}$"
export SUPABASE_KONG_DASHBOARD_USERNAME=
export SUPABASE_KONG_DASHBOARD_PASSWORD=
export SUPABASE_API_EXTERNAL_URL="https://supabase.${BASE_DOMAIN}$"
export SUPABASE_SITE_URL="https://supabase.${BASE_DOMAIN}$"
export SUPABASE_ADDITIONAL_REDIRECT_URLS=
export SUPABASE_SECRET_KEY_BASE=
export SUPABASE_VAULT_ENC_KEY=
export SUPABASE_DOCKER_SOCKET_LOCATION=

# Ente
export ENTE_DATABASE_PASSWORD=$(openssl rand -hex 48)
export ENTE_KEY_ENCRYPTION=$(openssl rand -base64 32)
export ENTE_KEY_HASH=$(openssl rand -base64 64)
export ENTE_JWT_SECRET=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')
```

# Cheat sheet
## Update all containers (dns server - rpi)
```bash
# Pull newest updates
git -C ${HOME}/homelab pull

# Update containers env vars
cd ${HOME}/dns-server
./applications.sh

# Update containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml build --pull --no-cache

# Shutdown containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml down

# Start containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml up --force-recreate -d
```

## Update all containers (homelab / debian)
```bash
# Pull newest updates
git -C ${HOME}/homelab pull

# Update containers env vars
cd ${HOME}/homelab
./applications.sh

# Update containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/ente/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/homeassistant/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull
# docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml pull

# Shutdown containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/ente/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/homeassistant/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down
# docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml down

# Start containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/ente/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/homeassistant/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up --force-recreate -d
# docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml up --force-recreate -d
```

## Backup containers data
```bash
sudo borg create ${BACKUP_PATH}::{now:%Y-%m-%d} ${DATA_PATH}
sudo borg prune --keep-weekly=4 --keep-monthly=3 ${BACKUP_PATH}
```

## Clear docker old images
```bash
docker system prune -af
```

# Misc guides
## Upgrade Immich database (or any other postgres)
```bash
export IMMICH_DATABASE_PASSWORD=

# Shutdown Immich
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down

# Backup Immich database volume
sudo cp -R ${DATA_PATH}/immich/volumes/postgres /tmp/postgres_backup

# Bring up only the postgres container
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d immich-postgres

# Backup the database
docker exec -t immich-postgres env PGPASSWORD=${IMMICH_DATABASE_PASSWORD} pg_dump -U immich -d immich -F c -f /tmp/immich.dump
docker cp immich-postgres:/tmp/immich.dump /tmp/immich.dump

# Shutdown the postgres container
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down immich-postgres

# Remove Immich database volume data
sudo rm -rf ${DATA_PATH}/immich/volumes/postgres/*

# Update docker-compose with new pg version

# Bring up only the postgres container
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull immich-postgres
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d immich-postgres

# Copy the dump file into the new container
docker cp /tmp/immich.dump immich-postgres:/tmp/immich.dump

# Create the database
docker exec -e PGPASSWORD="${IMMICH_DATABASE_PASSWORD}" immich-postgres \
  psql -U immich -c "CREATE DATABASE immich;"

# Restore the dump
docker exec -e PGPASSWORD="${IMMICH_DATABASE_PASSWORD}" immich-postgres \
  pg_restore -U immich -d immich /tmp/immich.dump

# Bring up the rest of the containers
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up --force-recreate -d
```

## Restore Immich
1. Restore volumes to correct directories
2. Start only postgres: `docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d immich-postgres`
3. Start the rest of the containers: `docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d`

## Setup existing disks
```bash
# Mount data device
sudo mkdir -p {/data,/backup}
sudo mount -t ext4 /dev/sda1 /data
sudo mount -t ext4 /dev/sdb1 /backup

# Auto-mount
sudo tee -a /etc/fstab << EOF

# data disk
UUID=$(lsblk -n -o UUID /dev/sda1) /data ext4 defaults 0 0

# backup disk
UUID=$(lsblk -n -o UUID /dev/sdb1) /backup ext4 defaults 0 0
EOF

sudo systemctl daemon-reload

# Change ownership to user
sudo chown -R $USER:$USER {/data,/backup}
```

## Setup new main data disk
```bash
# Delete old partition layout and re-read partition table
sudo wipefs -af /dev/sdb
sudo sgdisk --zap-all --clear /dev/sdb
sudo partprobe /dev/sdb

# Partition disk and re-read partition table
sudo sgdisk -n 1:0:0 -t 1:8300 /dev/sdb
sudo partprobe /dev/sdb

# Format partition to EXT4
sudo mkfs.ext4 /dev/sdb1

# Mount
sudo mkdir -p /data
sudo mount -t ext4 /dev/sdb1 /data

# Auto-mount
sudo tee -a /etc/fstab << EOF

# data disk
UUID=$(lsblk -n -o UUID /dev/sdb1) /data ext4 defaults 0 0
EOF

# Change ownership to user
sudo chown -R $USER:$USER /data
```

## Setup new backup disk
```bash
# Delete old partition layout and re-read partition table
sudo wipefs -af /dev/sda
sudo sgdisk --zap-all --clear /dev/sda
sudo partprobe /dev/sda

# Partition disk and re-read partition table
sudo sgdisk -n 1:0:0 -t 1:8300 /dev/sda
sudo partprobe /dev/sda

# Format partition to EXT4
sudo mkfs.ext4 /dev/sda1

# Mount
sudo mkdir -p /backup
sudo mount -t ext4 /dev/sda1 /backup

# Auto-mount
sudo tee -a /etc/fstab << EOF

# backup disk
UUID=$(lsblk -n -o UUID /dev/sda1) /backup ext4 defaults 0 0
EOF

# Change ownership to user
sudo chown -R $USER:$USER /backup
```

## Set static IP
```bash
# Check network settings
sudo nmcli

# Change IP address
sudo nmcli con modify 'enp34s0' ifname enp34s0 ipv4.method manual ipv4.addresses 10.100.100.253/24 gw4 10.100.100.1
sudo nmcli con down 'enp34s0'
sudo nmcli con up 'enp34s0' 
```

## Disable NVIDIA GPU
```bash
# References:
# https://discussion.fedoraproject.org/t/is-this-the-proper-way-to-disable-all-nvidia-gpu-drivers/130555
# https://wiki.archlinux.org/title/Hybrid_graphics#Fully_power_down_discrete_GPU

# Blacklist NVIDIA drivers
sudo tee /etc/modprobe.d/blacklist-nvidia.conf << EOF
blacklist nvidia
blacklist nouveau
options nouveau modeset=0
EOF

# Do not load NVIDIA drivers
# sudo grubby --update-kernel=ALL --args=rd.driver.blacklist=nouveau
# sudo grubby --update-kernel=ALL --args=modprobe.blacklist=nouveau
sudo tee /etc/default/grub.d/blacklist-nvidia.cfg << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"
EOF

# Remove NVIDIA UDEV rules
sudo tee /etc/udev/rules.d/00-remove-nvidia.rules << 'EOF'
# Remove NVIDIA USB xHCI Host Controller devices, if present
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"

# Remove NVIDIA USB Type-C UCSI devices, if present
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"

# Remove NVIDIA Audio devices, if present
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"

# Remove NVIDIA VGA/3D controller devices
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
EOF

# Recreate GRUB config
# sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo update-grub

# Regenerate initramfs
sudo dracut --regenerate-all --force
```

## Debian - Remove swap
- Partitioning method:
    - Guided - use entire disk and set up encrypted LVM
- Remove swap LV:
    - Configure the Logical Volume Manager
    - Select Swap logical volume
    - Delete logical volume
        - swap_1
    - Finish

# New services
* See [THIS](https://github.com/gjpin/homelab/commit/eaf9747716e9c0766c5a05d1258e6174e0b204d6) commit for example
* Add new env vars to secret (actual values)
* Add new env vars to ${HOME}/.bashrc.d/env (actual values)
* Create Docker network in the host
* Create new record in Cloudflare
* Commit and git pull from host
   * Run the new "block" that was added to applications.sh