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

# Forward traffic of privileged ports
sudo firewall-cmd --permanent --add-forward-port=port=5353:proto=udp:toport=53;
sudo firewall-cmd --permanent --add-forward-port=port=5353:proto=tcp:toport=53;

sudo firewall-cmd --permanent --add-forward-port=port=4443:proto=udp:toport=443;

# Open doors for WireGuard and Caddy TLS
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=51901/udp
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=4443/tcp
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=5353/udp
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=5353/tcp

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
# https://wiki.archlinux.org/title/Podman#Networking
# https://blog.podman.io/2024/03/podman-5-0-breaking-changes-in-detail/

# Install Podman
sudo dnf install -y podman podman-compose

# Turn on the container_manage_cgroup boolean to run containers with systemd
sudo setsebool -P container_manage_cgroup on

# Enable Podman socket
# systemctl --user enable podman.socket

# Allow rootless containers to bind to port 53 and up
# sudo tee /etc/sysctl.d/99-unprivileged-port.conf << EOF
# net.ipv4.ip_unprivileged_port_start=53
# EOF

# sudo sysctl --system

# Allow inter-containers communication with Pasta
# sudo tee /etc/containers/containers.conf << EOF
# [network]
# pasta_options = ["-a", "10.0.2.0", "-n", "24", "-g", "10.0.2.2", "--dns-forward", "10.0.2.3"]
# EOF

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