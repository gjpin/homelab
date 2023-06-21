#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

################################################
##### Update system and install base packages
################################################

# Update system
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# Install base packages
sudo apt install -y \
  wireguard \
  zstd \
  tar \
  apt-transport-https

################################################
##### AppArmor
################################################

# Install AppArmor
sudo apt -y install \
  apparmor \
  apparmor-utils \
  apparmor-profiles \
  apparmor-profiles-extra

# Enable AppArmor
sudo sed -i 's/rootwait/rootwait lsm=apparmor/g' /boot/cmdline.txt

################################################
##### Docker
################################################

# References:
# https://docs.docker.com/engine/install/debian/#install-using-the-repository

# Install dependencies
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker’s official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Setup Docker's repository
sudo tee /etc/apt/sources.list.d/docker.list << EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable
EOF

# Install Docker engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

#############################
# Automatic Docker volumes backup
#############################

mkdir -p /databackup/containers

# Backup script
sudo tee /usr/local/bin/automatic-backups.sh << 'EOF'
#!/usr/bin/bash

VOLUME_NAME_ARRAY=("caddy-webdav" "obsidian" "radicale" "vaultwarden")

for VOLUME_NAME in ${VOLUME_NAME_ARRAY[@]}; do
  tar -I zstd -cf /databackup/containers/$VOLUME_NAME-$(date +'%d-%m-%Y').tar.zstd -C /var/lib/docker/volumes/$VOLUME_NAME ./
  chown -R pi:pi /databackup/containers
done
EOF

sudo chmod +x /usr/local/bin/automatic-backups.sh

# Shutdown containers, backup their volumes and restart them every day
sudo tee /etc/systemd/system/automatic-backups.service << EOF
[Unit]
Description=Automatically backup docker containers

[Service]
Type=oneshot

ExecStart=/usr/bin/docker compose -f /etc/selfhosted/caddy/docker-compose.yml down
ExecStart=/usr/bin/docker compose -f /etc/selfhosted/obsidian/docker-compose.yml down
ExecStart=/usr/bin/docker compose -f /etc/selfhosted/radicale/docker-compose.yml down
ExecStart=/usr/bin/docker compose -f /etc/selfhosted/vaultwarden/docker-compose.yml down

ExecStart=/usr/local/bin/automatic-backups.sh

ExecStart=/usr/bin/docker compose -f /etc/selfhosted/caddy/docker-compose.yml up -d
ExecStart=/usr/bin/docker compose -f /etc/selfhosted/obsidian/docker-compose.yml up -d
ExecStart=/usr/bin/docker compose -f /etc/selfhosted/radicale/docker-compose.yml up -d
ExecStart=/usr/bin/docker compose -f /etc/selfhosted/vaultwarden/docker-compose.yml up -d
EOF

sudo tee /etc/systemd/system/automatic-backups.timer << EOF
[Unit]
Description=Automatically backup docker containers
RefuseManualStart=no
RefuseManualStop=no

[Timer]
Unit=automatic-backups.service
OnCalendar=*-*-* 04:00:00

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable automatic-backups.timer

################################################
##### Setup containers
################################################

sudo ./applications/caddy.sh
sudo ./applications/immich.sh
sudo ./applications/obsidian.sh
sudo ./applications/pihole.sh
sudo ./applications/radicale.sh
sudo ./applications/syncthing.sh
sudo ./applications/vaultwarden.sh