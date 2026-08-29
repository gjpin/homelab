#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
restic_restore="$root/bin/restore-legacy-restic"
postgres_restore="$root/bin/restore-legacy-postgres"
metadata="$root/config/legacy-migration.env"

for file in "$restic_restore" "$postgres_restore"; do
  bash -n "$file"
  [[ -x $file ]] || { printf 'restore tool is not executable: %s\n' "$file" >&2; exit 1; }
done

rg -q -- '--include /data/containers' "$restic_restore"
rg -q -- 'podman unshare tar --acls --xattrs --selinux --numeric-owner' "$restic_restore"
rg -q -- 'podman volume create --label' "$restic_restore"
rg -q -- 'legacy repository is never written|legacy Restic repository' "$restic_restore"
if rg -n 'restic (init|forget|prune)|systemctl --user (start|restart|enable)' "$restic_restore"; then
  printf 'legacy Restic restore tool contains a write or activation operation\n' >&2
  exit 1
fi

for mapping in \
  '[homelab-caddy-data]=caddy/volumes/caddy' \
  '[homelab-caddy-bookmarks]=caddy/volumes/bookmarks' \
  '[homelab-forgejo-data]=forgejo/volumes/data' \
  '[homelab-homeassistant-config]=homeassistant/volumes/homeassistant' \
  '[homelab-homeassistant-mosquitto-data]=homeassistant/volumes/mosquitto/data' \
  '[homelab-homeassistant-zigbee2mqtt]=homeassistant/volumes/zigbee2mqtt' \
  '[homelab-immich-data]=immich/volumes/immich' \
  '[homelab-radicale-collections]=radicale/volumes/radicale' \
  '[homelab-supernote-mariadb]=supernote/volumes/mariadb' \
  '[homelab-supernote-data]=supernote/volumes/supernote/data' \
  '[homelab-supernote-recycle]=supernote/volumes/supernote/recycle' \
  '[homelab-supernote-logs-app]=supernote/volumes/supernote/logs-app' \
  '[homelab-supernote-logs-cloud]=supernote/volumes/supernote/logs-cloud' \
  '[homelab-supernote-logs-web]=supernote/volumes/supernote/logs-web' \
  '[homelab-supernote-convert]=supernote/volumes/supernote/convert' \
  '[homelab-syncthing-data]=syncthing/volumes/syncthing' \
  '[homelab-vaultwarden-data]=vaultwarden/volumes/vaultwarden'; do
  rg -Fq "$mapping" "$restic_restore" || {
    printf 'legacy volume mapping is missing: %s\n' "$mapping" >&2
    exit 1
  }
done

rg -q -- 'migrate_forgejo_layout' "$restic_restore"
rg -q -- 'custom/conf/app.ini' "$restic_restore"

rg -q -- '--network none' "$postgres_restore"
rg -Fq -- '--user "${current_users[$workload]}"' "$postgres_restore"
rg -q -- '--cap-drop all' "$postgres_restore"
rg -q -- '--security-opt=no-new-privileges' "$postgres_restore"
rg -q -- '--pids-limit 1024' "$postgres_restore"
rg -q -- 'pg_dump' "$postgres_restore"
rg -q -- '--format=custom --no-owner' "$postgres_restore"
rg -q -- 'pg_restore' "$postgres_restore"
rg -q -- '--clean --if-exists --no-owner --exit-on-error' "$postgres_restore"
rg -q -- 'target PostgreSQL volume is not empty' "$postgres_restore"
if rg -n 'systemctl --user|homelab-(forgejo|immich)\.target' "$postgres_restore"; then
  printf 'PostgreSQL migration tool contains application activation\n' >&2
  exit 1
fi

rg -q '^LEGACY_FORGEJO_POSTGRES_IMAGE=[^[:space:]]+@sha256:[0-9a-f]{64}$' "$metadata"
rg -q '^LEGACY_IMMICH_POSTGRES_IMAGE=[^[:space:]]+@sha256:[0-9a-f]{64}$' "$metadata"

if rg -n 'HOMELAB_GIT_BRANCH=quadlets' "$root/systemd/user/homelab-reconcile.service"; then
  printf 'homelab-reconcile.service hardcodes quadlets branch\n' >&2
  exit 1
fi

printf 'legacy restore safety tests passed\n'
