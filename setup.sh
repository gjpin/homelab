#!/usr/bin/bash

################################################
##### Set variables
################################################

read -p "Hostname: " NEW_HOSTNAME
export NEW_HOSTNAME

################################################
##### General
################################################

# Set hostname
sudo hostnamectl set-hostname --pretty "${NEW_HOSTNAME}"
sudo hostnamectl set-hostname --static "${NEW_HOSTNAME}"

# Update system
sudo dnf upgrade -y --refresh

# Install common packages
sudo dnf install -y \
  bind-utils \
  kernel-tools \
  unzip \
  p7zip \
  p7zip-plugins \
  unrar \
  zstd \
  htop \
  xq \
  jq \
  fd-find \
  fzf \
  nano

# Create SSH directory and set permissions
mkdir -p ${HOME}/.ssh
chmod 700 ${HOME}/.ssh

# Create directory for bash configs
mkdir -p ${HOME}/.bashrc.d

################################################
##### Networking and Firewall
################################################

# References:
# https://www.procustodibus.com/blog/2021/07/wireguard-firewalld/

# TODO: create separate zone for WireGuard network

# Disable systemd-resolved (binds to port 53)
sudo systemctl disable --now systemd-resolved
sudo systemctl mask systemd-resolved

# Set Cloudflare as default DNS server
# /etc/resolv.conf
# nameserver 127.0.0.53
# options edns0 trust-ad
# search lan
echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" | sudo tee /etc/resolv.conf

# Restart Network Manager
sudo systemctl restart NetworkManager

# Open doors for WireGuard and Caddy TLS
sudo firewall-cmd --zone=FedoraServer --add-port=51901/udp
sudo firewall-cmd --zone=FedoraServer --add-port=443/tcp
sudo firewall-cmd --zone=FedoraServer --add-port=53/udp
sudo firewall-cmd --zone=FedoraServer --add-port=53/tcp
sudo firewall-cmd --runtime-to-permanent

################################################
##### WireGuard
################################################

# Install wireguard-tools
sudo dnf install -y wireguard-tools

# Create WireGuard folder
sudo mkdir -p /etc/wireguard/
sudo chmod 700 /etc/wireguard/

################################################
##### Podman
################################################

# References:
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux_atomic_host/7/html/managing_containers/running_containers_as_systemd_services_with_podman#starting_containers_with_systemd

# Install Podman
sudo dnf install -y podman podman-compose

# Enable Podman socket
systemctl --user enable podman.socket

# Set podman alias
tee ${HOME}/.bashrc.d/podman << EOF
alias docker="podman"
EOF

# Turn on the container_manage_cgroup boolean to run containers with systemd
sudo setsebool -P container_manage_cgroup on

# Allow rootless containers to bind to port 53 and up
sudo tee /etc/sysctl.d/99-unprivileged-port.conf << EOF
net.ipv4.ip_unprivileged_port_start=53
EOF

sudo sysctl --system

################################################
##### Unlock LUKS2 with TPM2 token
################################################

# References:
# https://fedoramagazine.org/use-systemd-cryptenroll-with-fido-u2f-or-tpm2-to-decrypt-your-disk/
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html

# Add tpm2-tss module to dracut
echo 'add_dracutmodules+=" tpm2-tss "' | sudo tee /etc/dracut.conf.d/tpm2.conf

# Enroll TPM2 as LUKS' decryption factor
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device auto /dev/nvme0n1p3

# Update crypttab
sudo sed -i "s|discard|&,tpm2-device=auto|" /etc/crypttab

# Regenerate initramfs
sudo dracut --regenerate-all --force

################################################
##### Next steps
################################################

# Reboot
# Go through applications/*.sh
# Start the containers