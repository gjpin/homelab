# Services
## Caddy
- webdav.${BASE_DOMAIN}
- Floccus bookmarks

## Immich
- photos.${BASE_DOMAIN}
- Photos

## Obsidian
- obsidian.${BASE_DOMAIN}

## Pi-Hole
- pihole.${BASE_DOMAIN}

## Radicale
- contacts.${BASE_DOMAIN}
- caldav

## Syncthing
- syncthing.${BASE_DOMAIN}

## Vaultwarden
- vault.${BASE_DOMAIN}

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