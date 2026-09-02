# Configure host WireGuard client on Fedora

This guide explains how to configure a WireGuard client connection on the
Fedora host using NetworkManager while preserving host SSH access and the
homelab's rootless Podman network topology.

## Prerequisites and package installation

Fedora includes the kernel WireGuard module by default. Install the user-space
tools (`wg` command):

```bash
sudo dnf install -y wireguard-tools
```

## Prepare the configuration directory

WireGuard configuration files contain unencrypted private keys and must be
restricted to root. Create `/etc/wireguard` with mode `0700`:

```bash
sudo install -d -m 0700 -o root -g root /etc/wireguard
```

Place your WireGuard client configuration file at `/etc/wireguard/wg0.conf`:

```bash
sudo install -m 0600 -o root -g root /path/to/source-wg.conf /etc/wireguard/wg0.conf
```

Confirm permissions on the configuration file:

```bash
ls -ld /etc/wireguard
ls -l /etc/wireguard/wg0.conf
```

The directory must be `drwx------` (`0700`) and the configuration file `-rw-------` (`0600`), owned by `root:root`.

## Verify `AllowedIPs` before importing

Before activating the connection, verify that the `[Peer]` section in
`/etc/wireguard/wg0.conf` does not conflict with existing networks:

1. **Do not include your local LAN subnet in `AllowedIPs`**:
   For example, if your local LAN is `192.168.8.0/24`, do not include
   `192.168.8.0/24` (or `192.168.8.1/24`) in `AllowedIPs`. WireGuard routes
   all matching destination traffic into the tunnel, which will divert replies
   to LAN clients and immediately drop active SSH sessions.
2. **Do not overlap the container range `10.200.0.0/16`**:
   The homelab uses deterministic subnets within `10.200.0.0/16` for rootless
   Podman networks. Host routes overlapping this range will cause
   `./bin/validate` to fail and disrupt internal container routing.

Set `AllowedIPs` to only the specific remote subnets or peer addresses you
need to reach (e.g. `10.10.0.0/24`).

## Setup with NetworkManager

Fedora manages host interfaces through NetworkManager. Import the configuration
into NetworkManager:

```bash
sudo nmcli connection import type wireguard file /etc/wireguard/wg0.conf
```

This creates a managed connection named `wg0`.

### Prevent default gateway hijacking

Unless this host is intended to route all Internet traffic through the VPN,
ensure the WireGuard connection does not replace your primary default route:

```bash
sudo nmcli connection modify wg0 ipv4.never-default yes
```

### Enable automatic connection at boot

Configure the connection to activate automatically when the system boots:

```bash
sudo nmcli connection modify wg0 connection.autoconnect yes
```

### Start the connection

Bring up the tunnel:

```bash
sudo nmcli connection up wg0
```

Verify that the interface is active and exchanging handshakes:

```bash
sudo wg show
nmcli connection show wg0
```

## Configure firewalld (optional)

By default, NetworkManager assigns the `wg0` interface to your host's default
firewalld zone (such as `FedoraServer` on Fedora Server, or `public`). Because
`bin/bootstrap-host` already opened TCP 443 (HTTPS) and Syncthing TCP/UDP 22000
in that default zone, no additional firewalld changes are usually required. You
can verify active zones with:

```bash
sudo firewall-cmd --get-active-zones
```

If you prefer to move `wg0` into a dedicated firewalld zone (such as `internal`),
ensure you also explicitly permit the necessary homelab services:

```bash
sudo firewall-cmd --permanent --zone=internal --add-interface=wg0
sudo firewall-cmd --permanent --zone=internal --add-service=https
sudo firewall-cmd --permanent --zone=internal --add-port=22000/tcp
sudo firewall-cmd --permanent --zone=internal --add-port=22000/udp
sudo firewall-cmd --reload
```

## Verification

After starting the connection, run the homelab validation script to confirm
that the new routing table does not conflict with container networks:

```bash
./bin/validate
./bin/status
```

## Management commands

- Stop the connection:
  ```bash
  sudo nmcli connection down wg0
  ```
- Disable autoconnect at boot:
  ```bash
  sudo nmcli connection modify wg0 connection.autoconnect no
  ```
- Delete the connection:
  ```bash
  sudo nmcli connection delete wg0
  ```
