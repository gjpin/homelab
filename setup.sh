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
  nano \
  git

# Create SSH directory and set permissions
mkdir -p ${HOME}/.ssh
chmod 700 ${HOME}/.ssh

# Create directory for bash configs
mkdir -p ${HOME}/.bashrc.d

################################################
##### Extend logical volume and filesystem
################################################

# References:
# https://discussion.fedoraproject.org/t/disk-resize-with-gparted-gone-wrong/131277/3
# https://discussion.fedoraproject.org/t/extending-root-partition-on-fedora-40-server/135194

# Extend logical volume and filesystem
sudo lvextend -An -r -l +100%FREE /dev/mapper/fedora*-root

# Backup volume groups
sudo vgcfgbackup

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
##### Networking and Firewall
################################################

# References:
# https://www.procustodibus.com/blog/2021/07/wireguard-firewalld/
# https://github.com/AdguardTeam/AdGuardHome/wiki/Docker#resolved-daemon
# https://github.com/containers/podman/issues/9089#issuecomment-1639914672
# https://bugzilla.redhat.com/show_bug.cgi?id=1445918

# TODO: create separate zone for WireGuard network

# Disable systemd-resolved DNS Stub Listener
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/disable-dns-stub-listener.conf << EOF
[Resolve]
DNSStubListener=no
EOF

sudo mv /etc/resolv.conf /etc/resolv.conf.backup
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved

# Open doors for WireGuard
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=51901/udp

# Open doors for Caddy (HTTPS)
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=443/tcp

# Open doors for Pi-Hole (DNS)
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=53/udp
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=53/tcp

# Open doors for Syncthing
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=22000/udp
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=22000/tcp
sudo firewall-cmd --permanent --zone=FedoraServer --add-port=21027/tcp

sudo firewall-cmd --reload

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
# https://github.com/containers/podman/discussions/24099#discussioncomment-10796176

# Install Podman
sudo dnf install -y podman podman-compose

# Turn on the container_manage_cgroup boolean to run containers with systemd
sudo setsebool -P container_manage_cgroup on

# Bind aardvark-dns to port 530
sudo tee /etc/containers/containers.conf << EOF
[network]
dns_bind_port=530
EOF

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