#!/usr/bin/bash

################################################
##### 
################################################

# Update all packages
sudo dnf update -y

################################################
##### WireGuard
################################################

# Install WireGuard tools
sudo dnf install -y wireguard-tools

# Create WireGuard directory
sudo mkdir -p /etc/wireguard
sudo chmod 700 /etc/wireguard

################################################
##### Kernel configurations
################################################

# References:
# https://www.kernel.org/doc/Documentation/vm/overcommit-accounting
# https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
# https://docs.k3s.io/security/hardening-guide

sudo tee /etc/sysctl.d/99-udp-max-buffer-size.conf << EOF
net.core.rmem_max=7500000
net.core.wmem_max=7500000
EOF

sudo tee /etc/sysctl.d/99-ipv4-ip-forward.conf << EOF
net.ipv4.ip_forward=1
EOF

sudo tee /etc/sysctl.d/90-kubelet.conf << EOF
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOF

# Reload configurations
sudo sysctl --system

################################################
##### k3s
################################################

# References:
# https://docs.k3s.io/installation/requirements
# https://docs.k3s.io/installation/configuration
# https://docs.k3s.io/security/hardening-guide
# https://docs.k3s.io/networking/basic-network-options

# Configure firewalld
sudo firewall-cmd --permanent --add-port=6443/tcp # apiserver
sudo firewall-cmd --permanent --add-port=51820/udp # flannel wireguard
sudo firewall-cmd --permanent --add-port=10250/tcp # kubelet / metrics server
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 # pods
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 # services
sudo firewall-cmd --reload

# Disable nm-cloud-setup
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer

# Create k3s directories
sudo mkdir -p /etc/rancher/k3s/config.yaml.d
sudo mkdir -p /var/lib/rancher/k3s/server/manifests

# k3s config
sudo curl -sfL https://raw.githubusercontent.com/gjpin/homelab/main/kubernetes/configs/k3s/config_server.yaml -o /etc/rancher/k3s/config.yaml

# Pod Security Admission policies
sudo curl -sfL https://raw.githubusercontent.com/gjpin/homelab/main/kubernetes/configs/k3s/pod_security_policies.yaml -o /var/lib/rancher/k3s/server/pod_security_policies.yaml

# Network policies
sudo curl -sfL https://raw.githubusercontent.com/gjpin/homelab/main/kubernetes/configs/k3s/network_policies.yaml -o /var/lib/rancher/k3s/server/manifests/network_policies.yaml

# Start k3s
curl -sfL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} sh -s - server

# Ensure that the Kubernetes PKI certificates have proper permissions
sudo chmod -R 600 /var/lib/rancher/k3s/server/tls/*.crt