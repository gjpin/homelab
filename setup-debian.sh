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
  nano \
  htop \
  lm-sensors

# Create SSH directory and set permissions
mkdir -p ${HOME}/.ssh
chmod 700 ${HOME}/.ssh

# Create directory for GRUB dropins
sudo mkdir -p /etc/default/grub.d

################################################
##### Setup backports
################################################

# References:
# https://backports.debian.org/Instructions/
# https://backports.debian.org/changes/bookworm-backports.html

# Get release codename
. /etc/os-release

# Add backports repo
sudo tee /etc/apt/sources.list.d/$VERSION_CODENAME-backports.list << EOF
deb http://deb.debian.org/debian $VERSION_CODENAME-backports main
EOF

# Update repos
sudo apt update

# Install latest kernel from backports
sudo apt install -y linux-image-amd64/$VERSION_CODENAME-backports

################################################
##### WireGuard
################################################

# Install wireguard tools
sudo apt install -y wireguard-tools

# Create WireGuard directory
sudo mkdir -p /etc/wireguard/
sudo chmod 700 /etc/wireguard/

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

# Reload configurations
sudo sysctl --system

################################################
##### AppArmor
################################################

# References:
# https://wiki.debian.org/AppArmor/HowToUse

# Ensure AppArmor is enabled
# sudo tee /etc/default/grub.d/apparmor.cfg << 'EOF'
# GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=1 security=apparmor"
# EOF

# sudo update-grub

# Install AppArmor userspace tools
sudo apt -y install \
  apparmor \
  apparmor-utils \
  auditd

# Install additional AppArmor profiles
sudo apt -y install \
  apparmor-profiles \
  apparmor-profiles-extra

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
##### ZRAM / swap
################################################

# References:
# https://wiki.archlinux.org/title/Zram
# https://blog.fernvenue.com/archives/using-zram-instead-of-swap/

# Install zram generator and zram tools
sudo apt install -y \
  systemd-zram-generator \
  zram-tools

# Configure zram generator
sudo tee /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
EOF

# Set page cluster
echo 'vm.page-cluster=0' | sudo tee /etc/sysctl.d/99-page-cluster.conf

# Set swappiness
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf

# Set vfs cache pressure
echo 'vm.vfs_cache_pressure=50' | sudo tee /etc/sysctl.d/99-vfs-cache-pressure.conf

# Daemon reload
sudo systemctl daemon-reload

# Enable zram on boot
sudo systemctl start /dev/zram0

################################################
##### Unlock LUKS2 with TPM2 token
################################################

# References:
# https://fedoramagazine.org/use-systemd-cryptenroll-with-fido-u2f-or-tpm2-to-decrypt-your-disk/
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html
# https://blog.fernvenue.com/archives/debian-with-luks-and-tpm-auto-decryption/
# https://forums.debian.net/viewtopic.php?t=158559

# Install dracut and tpm2-tools
sudo apt install -y dracut tpm2-tools

# Enroll TPM2 as LUKS' decryption factor
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p3

# Add tpm2-tss module to dracut
echo 'add_dracutmodules+=" tpm2-tss crypt "' | sudo tee /etc/dracut.conf.d/tpm2.conf

# Configure GRUB
sudo tee /etc/default/grub.d/luks-tpm2-unlock.cfg << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT rd.auto rd.luks=1"
EOF

sudo update-grub

# Update crypttab
sudo sed -i '/_crypt/s/^/# /' /etc/crypttab

# Regenerate initramfs
sudo dracut --regenerate-all --force