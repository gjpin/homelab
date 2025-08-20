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
  htop

# Install borgbackup
sudo apt install -y borgbackup

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
##### WireGuard
################################################

# Install wireguard tools
sudo apt install -y wireguard-tools

# Create WireGuard directory
sudo mkdir -p /etc/wireguard/
sudo chmod 700 /etc/wireguard/

################################################
##### Swap
################################################

# Disable swap temporarily
# sudo swapoff -a

# Disable swap permanently
# sudo dphys-swapfile swapoff
# sudo systemctl disable --now dphys-swapfile.service

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
sudo sed -i 's/rootwait/rootwait lsm=apparmor/g' /boot/firmware/cmdline.txt

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
# sudo ufw route allow from any to any port 53 comment 'Pi-hole DNS'

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

################################################
##### Next steps
################################################

# Reboot
# Go through applications/*.sh
# Start the containers