# Migrate Quadlet/Fedora volumes to Docker/Debian

This is a one-time cutover from the rootless Podman Quadlet host to a new
Debian Docker host. Quadlet backups run under `podman unshare`, so files in
Restic already have container UIDs.

Keep the Fedora host and the `pre-docker` snapshot until the first Docker-era
backup is verified.

## 1. Freeze the Quadlet host

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
~/current/bin/backup --tag pre-docker --leave-stopped-on-success
snapshot=$(<~/.local/state/homelab/last-backup-snapshot)
~/current/bin/restic snapshots --tag pre-docker
install -m 0600 ~/.local/state/homelab/backup-metadata/volume-map.tsv /tmp/volume-map.tsv
```

Copy `/tmp/volume-map.tsv`, the host age identity, and the restic password to
the operator workstation.

## 2. Install Debian and bootstrap the `docker` branch

```bash
sudo ./bin/bootstrap-host \
  --repo git@github.com:OWNER/REPOSITORY.git \
  --branch docker \
  --git-key ../github-deploy-key \
  --known-hosts ../github-known-hosts \
  --host-age-key ../host-age-keys.txt \
  --defer-forgejo-runner
```

Do not start `homelab.service` yet.

## 3. Create volumes and restore

As root, with `HOME=/home/homelab`:

```bash
set -Eeuo pipefail
export HOME=/home/homelab
cd /home/homelab/git/repository
mapfile -t volumes < <(./bin/lib.sh >/dev/null; rg --no-filename 'name: homelab-' compose | awk '{print $2}' | sort -u)
# explicit list:
volumes=(
  homelab-caddy-bookmarks homelab-caddy-config homelab-caddy-data
  homelab-forgejo-data homelab-forgejo-postgres
  homelab-homeassistant-config homelab-homeassistant-mosquitto-data
  homelab-homeassistant-zigbee2mqtt
  homelab-immich-data homelab-immich-machine-learning
  homelab-immich-postgres homelab-immich-postgres-config homelab-immich-redis
  homelab-radicale-collections
  homelab-searxng-cache homelab-searxng-redis
  homelab-syncthing-data
  homelab-vaultwarden-data
)
for volume in "${volumes[@]}"; do
  docker volume create --label homelab.application="${volume#homelab-}" "$volume" >/dev/null
done
```

Restore mapping (Quadlet name → Docker name). Cache volumes may start empty.

| Quadlet volume | Docker volume | Required |
| --- | --- | --- |
| `homelab-caddy-bookmarks` | same | yes |
| `homelab-caddy-config` | same | yes |
| `homelab-caddy-data` | same | yes |
| `homelab-forgejo-data` | same | yes |
| `homelab-forgejo-postgres` | same | yes |
| `homelab-homeassistant-config` | same | yes |
| `homelab-homeassistant-mosquitto-data` | same | yes |
| `homelab-homeassistant-zigbee2mqtt` | same | yes |
| `homelab-immich-data` | same | yes |
| `homelab-immich-postgres` | same | yes |
| `homelab-immich-postgres-config` | same | yes |
| `homelab-immich-machine-learning` | same | no |
| `homelab-immich-valkey` | `homelab-immich-redis` | no |
| `homelab-radicale-collections` | same | yes |
| `homelab-searxng-cache` | same | no |
| `homelab-searxng-valkey` | `homelab-searxng-redis` | no |
| `homelab-syncthing-data` | same | yes |
| `homelab-vaultwarden-data` | same | yes |

```bash
snapshot=SNAPSHOT_ID
while IFS=$'\t' read -r volume src; do
  dst_volume=$volume
  [[ $volume == homelab-immich-valkey ]] && dst_volume=homelab-immich-redis
  [[ $volume == homelab-searxng-valkey ]] && dst_volume=homelab-searxng-redis
  docker volume inspect "$dst_volume" >/dev/null
  dst=$(docker volume inspect -f '{{.Mountpoint}}' "$dst_volume")
  /home/homelab/git/repository/bin/restic restore "$snapshot:$src" --target "$dst"
done < volume-map.tsv
```

If Redis rejects a restored Valkey RDB, wipe that volume and continue. Photo,
vault, git, and HA data are not in Redis.

PostgreSQL majors must match (this branch uses 18).

The official Radicale image runs as uid 1000 and stores collections at
`/var/lib/radicale` on volume `homelab-radicale-collections`. After restore,
reown the volume if files still have the Alpine package uid 100:

```bash
chown -R 1000:1000 "$(docker volume inspect -f '{{.Mountpoint}}' homelab-radicale-collections)"
```

## 4. Start and verify

```bash
systemctl start homelab.service
docker ps
```

Check every hostname. Then:

```bash
sudo env HOME=/home/homelab /home/homelab/current/bin/backup --tag post-docker
```

Re-run bootstrap without `--defer-forgejo-runner` after DNS points at the new
host.

Keep the Fedora host powered off but retained until that snapshot is restored
successfully on a scratch volume.
