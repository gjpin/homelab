# Docker homelab

Debian host, rootful Docker Compose, SOPS with hybrid post-quantum age keys,
and a GitOps reconciler. Caddy terminates HTTPS on host port 443.

## Services

| Name | URL | Description | Internet egress |
| --- | --- | --- | --- |
| [Caddy](https://github.com/caddyserver/caddy) | bookmarks.${BASE_DOMAIN} | Authenticated bookmarks and WebDAV | Yes |
| [Forgejo](https://codeberg.org/forgejo/forgejo) | git.${BASE_DOMAIN} | Git server | Yes |
| [Home Assistant](https://github.com/home-assistant/core) | home.${BASE_DOMAIN} | Home automation | Yes |
| [Zigbee2MQTT](https://github.com/Koenkk/zigbee2mqtt) | home-zigbee.${BASE_DOMAIN} | Zigbee to MQTT | Yes |
| [Immich](https://github.com/immich-app/immich) | photos.${BASE_DOMAIN} | Photo backup | Yes |
| [Radicale](https://github.com/Kozea/Radicale) | contacts.${BASE_DOMAIN} | CardDAV | No |
| [SearXNG](https://github.com/searxng/searxng) | search.${BASE_DOMAIN} | Metasearch | Yes |
| [Syncthing](https://github.com/syncthing/syncthing) | syncthing.${BASE_DOMAIN} | File sync | No |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | vault.${BASE_DOMAIN} | Bitwarden-compatible server | No |

Inbound HTTP is only Caddy on TCP 443, plus Syncthing TCP/UDP 22000.

## Security model

- Production Docker is rootful. The locked `homelab` account is in the `docker`
  group (root-equivalent). Document that; do not pretend it is rootless.
- GitOps reconcile has no sudo. It talks to the Docker daemon as `homelab`.
- AppArmor is required. Containers use Docker's `docker-default` profile.
- Compose drops all capabilities, uses a read-only rootfs, `no-new-privileges`,
  and a 1024 PID limit. Caddy may add `NET_BIND_SERVICE`.
- Application networks are named and isolated. Backend/database networks are
  `internal: true`. Caddy never joins those. Docker assigns subnets.
- Secrets live in SOPS and are rendered under
  `/home/homelab/.local/state/homelab/rendered` (mode 0700).
- Images are digest-pinned. Renovate opens reviewed PRs; no automerge.
- Forgejo Actions runs as locked `forgejo-runner` with rootless Docker and
  nftables egress. It must not use the production Docker socket.

Official Postgres and Redis images start as root and drop to their service
user. Application images set an explicit non-root `user:` where they support it.
Home Assistant stays image-root because of s6.

## Prerequisites

- Debian (amd64 or arm64), cgroup v2, AppArmor enabled.
- `bin/bootstrap-host` installs apt packages, Docker CE, AppArmor, nftables,
  and checksum-pinned age (≥ 1.3.0), restic (≥ 0.19.1), sops, and forgejo-runner.
- Operator workstation: Bash 4+, Git, OpenSSH, `jq`, `ripgrep`, age 1.3+,
  SOPS 3.12+, `openssl`, `argon2`, Python 3 + bcrypt.
- Cloudflare zone for `BASE_DOMAIN`, no existing listener on TCP 443.
- Private GitHub repository and a read-only deploy key.
- Private S3-compatible bucket for restic (see [backups](docs/backups.md)).
- Zigbee coordinator with a stable `/dev/serial/by-id/...` name.

## Initial installation

1. Create a private GitHub repository.
2. On the workstation, this directory is the repository root. Work happens on
   the `docker` branch until you cut over.

   ```bash
   git checkout docker
   ./bin/validate
   ./tests/static.sh
   git push -u origin docker
   ```

3. Generate an unencrypted SSH deploy key and add it to the repository as a
   read-only deploy key. Collect GitHub's ED25519 host key and verify it.
4. Copy a trusted working tree plus the deploy key and known_hosts to the host.
5. On the host:

   ```bash
   cd ~/docker-bootstrap/source
   sudo ./bin/bootstrap-host \
     --repo git@github.com:OWNER/REPOSITORY.git \
     --branch docker \
     --git-key ../github-deploy-key \
     --known-hosts ../github-known-hosts
   ```

   Optional: `--data-disk /dev/disk/by-id/DEVICE` mounts XFS at `/var/lib/docker`.
   Record the printed `age1pq1...` host recipient.
6. On the workstation, generate the operator age identity (`age-keygen -pq`),
   create a Cloudflare DNS-01 token, and run `bin/init-secrets` with both
   recipients. Commit `secrets/secrets.sops.yaml` and `.sops.yaml`.
7. Re-run `bootstrap-host` so timezone, Zigbee udev, and runner egress apply.
8. `systemctl start homelab.service` (or wait for `homelab-reconcile.timer`).

Migrating from the Fedora Quadlet host: [docs/quadlet-to-docker.md](docs/quadlet-to-docker.md).

## GitOps

`homelab-reconcile.timer` fetches `origin/<branch>`, archives an immutable
release, validates, renders SOPS, and `docker compose up` for changed workloads.
Only fast-forwards are applied.

Host tools (age, restic, sops, forgejo-runner) update daily from
`config/host-tools.env` via `/usr/local/lib/homelab/install-*`.

## Backup

Cold restic snapshots of named Docker volumes. See [docs/backups.md](docs/backups.md).

## Validation

```bash
./bin/validate
./tests/static.sh
./bin/e2e --workload WORKLOAD
./bin/e2e
```
