#!/usr/bin/bash

################################################
##### Update system and install base packages
################################################

# References:
# https://wiki.archlinux.org/title/Borg_backup

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
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apache2-utils \
  wakeonlan \
  git \
  nano

# Install borgbackup
sudo apt install -y borgbackup

# Disable the DNSStubListener to unbind it from port 53
sudo sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

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

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Setup Docker's repository
sudo tee /etc/apt/sources.list.d/docker.list << EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF

# Install Docker engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER

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
##### Next steps
################################################

# Reboot
# Go through applications/*.sh
# Start the containers