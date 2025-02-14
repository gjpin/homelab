#!/usr/bin/bash

# Become root, in case sudo is not yet installed
# su -
# adduser $username sudo

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
  apache2-utils \
  wakeonlan

# Install borgbackup
sudo apt install -y borgbackup

# Install AppArmor utils
sudo apt -y install \
  apparmor \
  apparmor-utils \
  apparmor-profiles \
  apparmor-profiles-extra \
  auditd

################################################
##### GRUB
################################################

# Disable the GRUB menu selection
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_HIDDEN_TIMEOUT=.*/GRUB_HIDDEN_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=true/' /etc/default/grub

# If the above settings are missing, add them
grep -q '^GRUB_TIMEOUT=' /etc/default/grub || echo 'GRUB_TIMEOUT=0' | sudo tee -a /etc/default/grub
grep -q '^GRUB_HIDDEN_TIMEOUT=' /etc/default/grub || echo 'GRUB_HIDDEN_TIMEOUT=0' | sudo tee -a /etc/default/grub
grep -q '^GRUB_HIDDEN_TIMEOUT_QUIET=' /etc/default/grub || echo 'GRUB_HIDDEN_TIMEOUT_QUIET=true' | sudo tee -a /etc/default/grub

# Regenerate GRUB configuration
sudo update-grub

################################################
##### Auto-unlock LUKS with TPM2
################################################

# Install tpm2-tools
sudo apt install -y tpm2-tools

# Enroll TPM2 Key in LUKS
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p3

# Update /etc/crypttab
sudo sed -i 's/\bluks\b/tpm2-device=auto,&/' /etc/crypttab

# Regenerate the initramfs to include TPM2 unlock support
sudo update-initramfs -u -k all

# Ensure GRUB includes the correct kernel parameters
sudo update-grub

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

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker's repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker packages
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to Docker group
sudo usermod -aG docker $USER

################################################
##### Next steps
################################################

# Reboot
# Go through applications/*.sh
# Start the containers