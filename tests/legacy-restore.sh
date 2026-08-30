#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"
restic_restore="$root/bin/restore-legacy-restic"
postgres_restore="$root/bin/restore-legacy-postgres"
metadata="$root/config/legacy-migration.env"

for file in "$restic_restore" "$postgres_restore"; do
  bash -n "$file"
  [[ -x $file ]] || { printf 'restore tool is not executable: %s\n' "$file" >&2; exit 1; }
done
bash -n "$root/bin/lib.sh"

[[ $(unquote_env_value '"hello world"') == 'hello world' ]] || {
  printf 'unquote_env_value failed to strip double quotes\n' >&2
  exit 1
}
[[ $(unquote_env_value "'secret'") == 'secret' ]] || {
  printf 'unquote_env_value failed to strip single quotes\n' >&2
  exit 1
}
[[ $(unquote_env_value 'unquoted') == 'unquoted' ]] || {
  printf 'unquote_env_value changed an unquoted value\n' >&2
  exit 1
}
[[ $(unquote_env_value '"s3:https://s3.example.com/my bucket"') == 's3:https://s3.example.com/my bucket' ]] || {
  printf 'unquote_env_value failed on a quoted URL with spaces\n' >&2
  exit 1
}

forgejo_tree=$(mktemp -d "${TMPDIR:-/tmp}/homelab-forgejo-rewrite.XXXXXX")
cleanup_forgejo_tree() {
  rm -rf -- "$forgejo_tree"
}
trap cleanup_forgejo_tree EXIT
mkdir -p "$forgejo_tree/gitea/conf" "$forgejo_tree/gitea/avatars" "$forgejo_tree/git/repositories"
cat >"$forgejo_tree/gitea/conf/app.ini" <<'EOF'
WORK_PATH = /data
APP_DATA_PATH = /data/gitea
ROOT = /data/git/repositories
EOF
printf 'avatar\n' >"$forgejo_tree/gitea/avatars/user.png"
printf 'repo\n' >"$forgejo_tree/git/repositories/example"
rewrite_legacy_forgejo_tree "$forgejo_tree"
[[ -f $forgejo_tree/custom/conf/app.ini ]] || {
  printf 'Forgejo rewrite did not move app.ini to custom/conf\n' >&2
  exit 1
}
[[ -f $forgejo_tree/gitea/avatars/user.png ]] || {
  printf 'Forgejo rewrite flattened gitea/avatars\n' >&2
  exit 1
}
[[ -d $forgejo_tree/gitea ]] || {
  printf 'Forgejo rewrite removed the gitea/ tree\n' >&2
  exit 1
}
[[ -f $forgejo_tree/git/repositories/example ]] || {
  printf 'Forgejo rewrite disturbed git repositories\n' >&2
  exit 1
}
rg -q -- 'WORK_PATH = /var/lib/gitea$' "$forgejo_tree/custom/conf/app.ini" || {
  printf 'Forgejo rewrite did not convert WORK_PATH = /data\n' >&2
  exit 1
}
rg -q -- 'APP_DATA_PATH = /var/lib/gitea/gitea$' "$forgejo_tree/custom/conf/app.ini" || {
  printf 'Forgejo rewrite did not convert APP_DATA_PATH\n' >&2
  exit 1
}
rg -q -- 'ROOT = /var/lib/gitea/git/repositories$' "$forgejo_tree/custom/conf/app.ini" || {
  printf 'Forgejo rewrite did not convert repository ROOT\n' >&2
  exit 1
}

rg -q -- '--include /data/containers' "$restic_restore"
rg -q -- '--list-snapshots' "$restic_restore"
rg -q -- '--path /data/containers' "$restic_restore"
rg -q -- 'podman unshare tar --acls --xattrs --selinux --numeric-owner' "$restic_restore"
rg -q -- 'podman volume create --label' "$restic_restore"
rg -q -- 'legacy repository is never written|legacy Restic repository' "$restic_restore"
rg -Fq -- 'rewrite_legacy_forgejo_tree' "$restic_restore"
rg -Fq -- 'rewrite_legacy_forgejo_tree' "$root/bin/lib.sh"
if rg -n 'restic (init|forget|prune)|systemctl --user (start|restart|enable)' "$restic_restore"; then
  printf 'legacy Restic restore tool contains a write or activation operation\n' >&2
  exit 1
fi
if rg -n 'mv "\$item" "\$mountpoint/\$base"' "$restic_restore" "$root/bin/lib.sh"; then
  printf 'Forgejo rewrite still flattens gitea/* onto the volume root\n' >&2
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
rg -q -- 'custom/conf/app.ini' "$root/bin/lib.sh"

rg -q -- '--network none' "$postgres_restore"
rg -Fq -- '--user "${current_users[$workload]}"' "$postgres_restore"
rg -q -- '--cap-drop all' "$postgres_restore"
rg -q -- '--security-opt=no-new-privileges' "$postgres_restore"
rg -q -- '--pids-limit 1024' "$postgres_restore"
rg -q -- 'pg_dump' "$postgres_restore"
rg -q -- '--format=custom --no-owner --no-privileges' "$postgres_restore"
rg -q -- 'pg_restore' "$postgres_restore"
rg -q -- '--clean --if-exists --no-owner --no-privileges --exit-on-error' "$postgres_restore"
rg -q -- 'target PostgreSQL volume is not empty' "$postgres_restore"
rg -q -- 'remove it with: rm -rf --' "$postgres_restore"
rg -q -- 'recreate only that empty volume with: podman volume rm' "$postgres_restore"
rg -q -- 'remove it with: rm -rf --' "$restic_restore"
rg -q -- 'remove it with: podman volume rm' "$restic_restore"
rg -q -- 'LEGACY_FORGEJO_POSTGRES_IMAGE\|LEGACY_IMMICH_POSTGRES_IMAGE\|LEGACY_SUPERNOTE_MARIADB_IMAGE' \
  "$postgres_restore"
rg -Fq -- 'legacy_config_volume="homelab-legacy-${workload}-config-$$"' "$postgres_restore"
rg -Fq -- '--volume "$legacy_config_volume:/etc/postgresql:U"' "$postgres_restore"
if ! awk '
  /^run_legacy_dump\(\)/ { in_dump=1 }
  /^run_current_restore\(\)/ { in_dump=0 }
  in_dump && /legacy_config_volume=/ { created=1 }
  in_dump && /\/etc\/postgresql:U/ { mounted=1 }
  END { exit(created && mounted ? 0 : 1) }
' "$postgres_restore"; then
  printf 'Immich dump path does not create a throwaway /etc/postgresql volume\n' >&2
  exit 1
fi
eval "$(awk '
  /^load_migration_env\(\)/ { keep=1 }
  keep { print }
  keep && /^}/ { exit }
' "$postgres_restore")"
load_migration_env "$metadata"
[[ -n ${LEGACY_SUPERNOTE_MARIADB_IMAGE:-} ]] || {
  printf 'load_migration_env rejected LEGACY_SUPERNOTE_MARIADB_IMAGE\n' >&2
  exit 1
}
quoted_migration_env=$(mktemp "${TMPDIR:-/tmp}/homelab-legacy-migration.XXXXXX")
cleanup_quoted_env() {
  rm -f -- "$quoted_migration_env"
  cleanup_forgejo_tree
}
trap cleanup_quoted_env EXIT
digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cat >"$quoted_migration_env" <<EOF
LEGACY_FORGEJO_POSTGRES_IMAGE="docker.io/library/postgres:17@sha256:${digest}"
LEGACY_IMMICH_POSTGRES_IMAGE='ghcr.io/immich-app/postgres:17@sha256:${digest}'
LEGACY_SUPERNOTE_MARIADB_IMAGE=docker.io/library/mariadb:11.8.3-noble@sha256:${digest}
EOF
load_migration_env "$quoted_migration_env"
[[ $LEGACY_FORGEJO_POSTGRES_IMAGE == "docker.io/library/postgres:17@sha256:${digest}" ]] || {
  printf 'load_migration_env did not unquote a double-quoted image\n' >&2
  exit 1
}
[[ $LEGACY_IMMICH_POSTGRES_IMAGE == "ghcr.io/immich-app/postgres:17@sha256:${digest}" ]] || {
  printf 'load_migration_env did not unquote a single-quoted image\n' >&2
  exit 1
}
cat >"$quoted_migration_env" <<EOF
LEGACY_FORGEJO_POSTGRES_IMAGE=docker.io/library/postgres:17@sha256:${digest}
LEGACY_IMMICH_POSTGRES_IMAGE=ghcr.io/immich-app/postgres:17@sha256:${digest}
EOF
load_migration_env "$quoted_migration_env"
[[ -z ${LEGACY_SUPERNOTE_MARIADB_IMAGE:-} ]] || {
  printf 'load_migration_env required the optional MariaDB image key\n' >&2
  exit 1
}
if rg -n 'mariadb-dump|mysqldump' "$postgres_restore"; then
  printf 'PostgreSQL restore tool unexpectedly dumps MariaDB\n' >&2
  exit 1
fi
if rg -n 'systemctl --user|homelab-(forgejo|immich)\.target' "$postgres_restore"; then
  printf 'PostgreSQL migration tool contains application activation\n' >&2
  exit 1
fi

rg -q '^LEGACY_FORGEJO_POSTGRES_IMAGE=[^[:space:]]+@sha256:[0-9a-f]{64}$' "$metadata"
rg -q '^LEGACY_IMMICH_POSTGRES_IMAGE=[^[:space:]]+@sha256:[0-9a-f]{64}$' "$metadata"
rg -q '^LEGACY_SUPERNOTE_MARIADB_IMAGE=[^[:space:]]+@sha256:[0-9a-f]{64}$' "$metadata"

if rg -n 'HOMELAB_GIT_BRANCH=quadlets' "$root/systemd/user/homelab-reconcile.service"; then
  printf 'homelab-reconcile.service hardcodes quadlets branch\n' >&2
  exit 1
fi

printf 'legacy restore safety tests passed\n'
