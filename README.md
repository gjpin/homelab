# Services
| Name | URL | Description | Access to internet |
| --- | --- | --- | --- |
| [Caddy](https://github.com/caddyserver/caddy) | bookmarks.${BASE_DOMAIN} | Web server and reverse proxy | Yes |
| [Immich](https://github.com/immich-app/immich) | photos.${BASE_DOMAIN} | Photo and video backup solution | No |
| [Obsidian LiveSync](https://github.com/vrtmrz/obsidian-livesync) | obsidian.${BASE_DOMAIN} | Community-implemented synchronization plugin | No |
| [Pi-hole](https://github.com/pi-hole/pi-hole) | pihole.${BASE_DOMAIN} | DNS sinkhole | Yes |
| [Radicale](https://github.com/Kozea/Radicale) | contacts.${BASE_DOMAIN} | CardDAV (contact) server | No |
| [Syncthing](https://github.com/syncthing/syncthing) | syncthing.${BASE_DOMAIN} | Continuous File Synchronization | Yes |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | vault.${BASE_DOMAIN} | Unofficial Bitwarden compatible server | No |

# How to
1. Create DNS entries in Cloudflare, pointing to Wireguard's internal address
2. Set env vars
3. Go through setup.sh
4. Configure and enable WireGuard `sudo systemctl enable --now wg-quick@wg0`
5. Start containers:
```bash
sudo docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
sudo docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull
sudo docker compose -f ${DATA_PATH}/obsidian/docker/docker-compose.yml pull
sudo docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml build --pull --no-cache
sudo docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml build --pull --no-cache
sudo docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml pull
sudo docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml pull

sudo docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up -d
sudo docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up -d
sudo docker compose -f ${DATA_PATH}/obsidian/docker/docker-compose.yml up -d
sudo docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml up -d
sudo docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml up -d
sudo docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml up -d
sudo docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml up -d
```

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

## New vars
```bash
export CADDY_PASSWORD=$(openssl rand -hex 48)
export CADDY_HASHED_PASSWORD=$(sudo docker run caddy:2-alpine caddy hash-password --plaintext ${CADDY_PASSWORD})
export CADDY_CLOUDFLARE_TOKEN=taken from Cloudflare

export IMMICH_DATABASE_PASSWORD=$(openssl rand -hex 48)
export IMMICH_JWT_SECRET=$(openssl rand -hex 48)

export OBSIDIAN_COUCHDB_PASSWORD=$(openssl rand -hex 48)

export PIHOLE_ADMIN_TOKEN=$(openssl rand -hex 48)
export PIHOLE_WEBPASSWORD=$(openssl rand -hex 48)

export RADICALE_PASSWORD=$(openssl rand -hex 48)
export RADICALE_USER_PASSWORD=$(htpasswd -n -b admin ${RADICALE_PASSWORD})

export VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -hex 48)
```

## Re-use vars
```bash
export CADDY_HASHED_PASSWORD=
export CADDY_CLOUDFLARE_TOKEN=

export IMMICH_DATABASE_PASSWORD=
export IMMICH_JWT_SECRET=

export OBSIDIAN_COUCHDB_PASSWORD=

export PIHOLE_ADMIN_TOKEN=
export PIHOLE_WEBPASSWORD=

export RADICALE_USER_PASSWORD=

export VAULTWARDEN_ADMIN_TOKEN=
```

# Cheat sheet
## Stop all containers
```bash
sudo docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
sudo docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down
sudo docker compose -f ${DATA_PATH}/obsidian/docker/docker-compose.yml down
sudo docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml down
sudo docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml down
sudo docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml down
sudo docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml down
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
/dev/sda1 /data ext4 defaults 0 0
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
/dev/sdb1 /backup ext4 defaults 0 0
EOF

# Change ownership to user
sudo chown -R $USER:$USER /backup
```