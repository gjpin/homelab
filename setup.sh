#!/usr/bin/bash

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
  apt-transport-https \
  apache2-utils

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
##### Setup containers
################################################

sudo ./applications/caddy.sh
sudo ./applications/immich.sh
sudo ./applications/obsidian.sh
sudo ./applications/pihole.sh
sudo ./applications/radicale.sh
sudo ./applications/syncthing.sh
sudo ./applications/vaultwarden.sh