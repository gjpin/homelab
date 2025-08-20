#!/usr/bin/bash

################################################
##### Repositories
################################################

# Ensure repos are correct
sudo tee /etc/apt/sources.list.d/debian.sources << 'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

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
  lm-sensors \
  udisks2 \
  unzip \
  jq

# Install borgbackup
sudo apt install -y borgbackup

# Create SSH directory and set permissions
mkdir -p ${HOME}/.ssh
chmod 700 ${HOME}/.ssh

# Create directory for GRUB dropins
sudo mkdir -p /etc/default/grub.d

# bashrc.d
mkdir -p ${HOME}/.bashrc.d
tee -a ${HOME}/.bashrc << 'EOF'

# Source .bashrc.d files
if [ -d ~/.bashrc.d ]; then
        for rc in ~/.bashrc.d/*; do
                if [ -f "$rc" ]; then
                        . "$rc"
                fi
        done
fi

unset rc
EOF

################################################
##### Setup backports
################################################

# References:
# https://backports.debian.org/Instructions/
# https://backports.debian.org/changes/bookworm-backports.html

# Get release codename
# . /etc/os-release

# Add backports repo
# sudo tee /etc/apt/sources.list.d/$VERSION_CODENAME-backports.list << EOF
# deb http://deb.debian.org/debian $VERSION_CODENAME-backports main
# EOF

# Update repos
# sudo apt update

# Install latest kernel from backports
# sudo apt install -y linux-base/$VERSION_CODENAME-backports
# sudo apt install -y linux-image-amd64/$VERSION_CODENAME-backports

################################################
##### WireGuard
################################################

# Install wireguard tools
sudo apt install -y wireguard-tools

# Create WireGuard directory
sudo mkdir -p /etc/wireguard/
sudo chmod 700 /etc/wireguard/

################################################
##### Networking and Firewall
################################################

# Install NetworkManager
sudo apt install -y network-manager

################################################
##### Kernel configurations
################################################

# References:
# https://www.kernel.org/doc/Documentation/vm/overcommit-accounting
# https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes

sudo sysctl vm.overcommit_memory=1
sudo tee /etc/sysctl.d/99-overcommit-memory.conf << EOF
vm.overcommit_memory=1
EOF

sudo tee /etc/sysctl.d/99-udp-max-buffer-size.conf << EOF
net.core.rmem_max=7500000
net.core.wmem_max=7500000
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
sudo tee -a /etc/apt/sources.list.d/debian.sources << 'EOF'

Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Install Docker engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER

################################################
##### Samba
################################################

# References:
# https://wiki.debian.org/Samba/ServerSimple
# https://wiki.archlinux.org/title/Samba

# Make the server discoverable
sudo apt install -y avahi-daemon

# Install samba packages
sudo apt install -y samba samba-client

# Add Samba users
sudo smbpasswd -a $USER

# Add Samba configs
sudo tee -a /etc/samba/smb.conf << EOF

[Media]
   path = /mnt/Movies
   browseable = yes
   read only = yes
   guest ok = yes
   force user = nobody
EOF

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

################################################
##### UFW
################################################

# References:
# https://wiki.debian.org/Uncomplicated%20Firewall%20%28ufw%29
# https://wiki.archlinux.org/title/Uncomplicated_Firewall

# Install UFW
sudo apt install -y ufw

# Configure UFW default behaviour
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Configure rules for SSH / Wireguard
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 51900 comment 'Wireguard'

# Configure rules for Docker containers
# sudo ufw route allow proto tcp from any to any port 443 comment 'Caddy HTTPS'
# sudo ufw route allow from any to any port 22000 comment 'Syncthing'

# Prevent Docker from overriding UFW
# https://github.com/chaifeng/ufw-docker
sudo tee -a /etc/ufw/after.rules << 'EOF'

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
EOF

# Restart UFW service
sudo systemctl restart ufw

# Enable UFW
sudo ufw enable