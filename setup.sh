#!/usr/bin/bash

################################################
##### Update system and install base packages
################################################

# Update system
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y

# Install base packages
sudo apt install -y \
  wireguard \
  zstd \
  tar \
  apt-transport-https \
  apache2-utils \
  wakeonlan

################################################
##### Swap
################################################

# Disable swap temporarily
sudo swapoff -a

# Disable swap permanently
sudo dphys-swapfile swapoff
sudo systemctl disable --now dphys-swapfile.service

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

################################################
##### Kernel configurations
################################################

# References:
# https://www.kernel.org/doc/Documentation/vm/overcommit-accounting
# https://github.com/lucas-clemente/quic-go/wiki/UDP-Receive-Buffer-Size

sudo sysctl vm.overcommit_memory=1
sudo tee /etc/sysctl.d/99-overcommit-memory.conf << EOF
vm.overcommit_memory=1
EOF

sudo sysctl net.core.rmem_max=2500000
sudo tee /etc/sysctl.d/99-udp-max-buffer-size.conf << EOF
net.core.rmem_max=2500000
EOF

sudo sysctl net.ipv4.ip_forward=1
sudo tee /etc/sysctl.d/99-ipv4-ip-forward.conf << EOF
net.ipv4.ip_forward=1
EOF

################################################
##### Automated backups and updates
################################################

# References:
# https://wiki.archlinux.org/title/Borg_backup

# Install borgbackup
sudo apt install -y borgbackup

# Create backup and update script
sudo tee /usr/local/bin/backup-update-containers.sh << EOF
#!/usr/bin/bash

# Update system
apt update
apt full-upgrade -y
apt autoremove -y

# Update containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml build --pull --no-cache

# Shutdown containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml down

# Backup containers data
borg create /backup/containers::{now:%Y-%m-%d} ${DATA_PATH}
borg prune --keep-weekly=4 --keep-monthly=3 ${BACKUP_PATH}

# Start containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml up --force-recreate -d

# Clear docker data
docker system prune -af
EOF

sudo chmod +x /usr/local/bin/backup-update-containers.sh

# Create systemd timer
sudo tee /etc/systemd/system/backup-update-containers.service << EOF
[Unit]
Description=Automatically backup and update system/containers

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-update-containers.sh
EOF

sudo tee /etc/systemd/system/backup-update-containers.timer << EOF
[Unit]
Description=Automatically backup and update system/containers
RefuseManualStart=no
RefuseManualStop=no

[Timer]
Unit=backup-update-containers.service
OnCalendar=Sat *-*-* 05:00:00

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now backup-update-containers.timer

################################################
##### Next steps
################################################

# Reboot
# Go through applications/*.sh
# Start the containers