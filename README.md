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

# Getting started
1. Create DNS entries in Cloudflare, pointing to Wireguard's internal address
2. Set env vars (see below)
3. Go through setup.sh
4. Configure and enable WireGuard `sudo systemctl enable --now wg-quick@wg0`
5. Start containers:
```bash
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml pull

docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml up --force-recreate -d
```
6. Create borg repo (if not created yet): `borg init --encryption=none /backup/containers`

# Paths
```bash
${DATA_PATH}/${SERVICE}/docker: Dockerfile / docker-compose.yml / config.env
${DATA_PATH}/${SERVICE}/configs: service configurations
${DATA_PATH}/${SERVICE}/volumes: persistent data created by the services
```

# Env vars
## Common
```bash
export BASE_DOMAIN=domain.com
export DATA_PATH=/data/containers
export BACKUP_PATH=/backup/containers
```

## Configuration
```bash
# Caddy
export CADDY_PASSWORD=$(openssl rand -hex 48)
export CADDY_HASHED_PASSWORD=$(docker run caddy:2-alpine caddy hash-password --plaintext ${CADDY_PASSWORD})
export CADDY_CLOUDFLARE_TOKEN=taken from Cloudflare

# Immich
export IMMICH_DATABASE_PASSWORD=$(openssl rand -hex 48)
export IMMICH_JWT_SECRET=$(openssl rand -hex 48)

# Obsidian
export OBSIDIAN_COUCHDB_PASSWORD=$(openssl rand -hex 48)

# Pi-Hole
export PIHOLE_ADMIN_TOKEN=$(openssl rand -hex 48)
export PIHOLE_WEBPASSWORD=$(openssl rand -hex 48)

# Technitium
export TECHNITIUM_ADMIN_PASSWORD=$(openssl rand -hex 48)

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
```

# Cheat sheet
## Update all containers
```bash
# Update system
apt update
apt full-upgrade -y
apt autoremove -y

# Update containers
# docker compose -f ${DATA_PATH}/technitium/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml pull

# Shutdown containers
# docker compose -f ${DATA_PATH}/technitium/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml down

# Backup containers data
borg create /backup/containers::{now:%Y-%m-%d} ${DATA_PATH}
borg prune --keep-weekly=4 --keep-monthly=3 ${BACKUP_PATH}

# Start containers
# docker compose -f ${DATA_PATH}/technitium/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml up --force-recreate -d

# Clear docker data
docker system prune -af
```

## Restore Immich
1. Restore volumes to correct directories
2. Start only postgres: `docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d immich-postgres`
3. Start the rest of the containers: `docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d`

# Setup disks
## Main data disk
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
sudo mkdir -p /data
sudo mount -t ext4 /dev/sda1 /data

# Auto-mount
sudo tee -a /etc/fstab << EOF

# data disk
UUID=$(lsblk -n -o UUID /dev/sda1) /data ext4 defaults 0 0
EOF

# Change ownership to user
sudo chown -R $USER:$USER /data
```

## Backup disk
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
sudo mkdir -p /backup
sudo mount -t ext4 /dev/sdb1 /backup

# Auto-mount
sudo tee -a /etc/fstab << EOF

# backup disk
UUID=$(lsblk -n -o UUID /dev/sdb1) /backup ext4 defaults 0 0
EOF

# Change ownership to user
sudo chown -R $USER:$USER /backup
```