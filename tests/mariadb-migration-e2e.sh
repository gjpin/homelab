#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$source_root/bin/lib.sh"

require_command find
require_command jq
require_command podman
require_command sed
require_command tar

if ! podman info >/dev/null 2>&1; then
  die "Podman is not running or unavailable; real container E2E migration test must run in a Podman environment"
fi

mariadb11_image="docker.io/library/mariadb:11.8.3-noble@sha256:ae6119716edac6998ae85508431b3d2e666530ddf4e94c61a10710caec9b0f71"
if [[ -f "$source_root/config/legacy-migration.env" ]]; then
  configured=$(sed -n 's/^LEGACY_SUPERNOTE_MARIADB_IMAGE=//p' "$source_root/config/legacy-migration.env")
  [[ -n $configured ]] && mariadb11_image=$configured
fi

target_unit="$source_root/incubator/supernote/quadlet/supernote-mariadb.container"
[[ -f $target_unit ]] || die "target unit not found: $target_unit"
mariadb12_image=$(sed -n 's/^Image=//p' "$target_unit")
[[ -n $mariadb12_image ]] || die "missing Image in $target_unit"

test_parent=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/homelab-mariadb-e2e.XXXXXX")
test_volume="homelab-e2e-mariadb-$$-$(date +%s)"
root_secret="homelab-e2e-mariadb-root-$$"
user_secret="homelab-e2e-mariadb-user-$$"
seed_container="homelab-e2e-mariadb-seed-$$"
verify_container="homelab-e2e-mariadb-verify-$$"
root_password='e2e-mariadb-root-password'
user_password='e2e-mariadb-user-password'
install -d -m 0700 "$test_parent/runtime"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$test_parent/runtime}"

cleanup() {
  local rc=$?
  set +e
  podman rm -f "$seed_container" "$verify_container" >/dev/null 2>&1 || true
  podman volume rm -f "$test_volume" >/dev/null 2>&1 || true
  podman secret rm -f "$root_secret" "$user_secret" >/dev/null 2>&1 || true
  rm -rf -- "$test_parent"
  trap - EXIT
  exit "$rc"
}
trap cleanup EXIT

info "creating real Podman test volume: $test_volume"
podman volume create --label io.containers.systemd.application=supernote "$test_volume" >/dev/null
printf '%s' "$root_password" | podman secret create "$root_secret" -
printf '%s' "$user_password" | podman secret create "$user_secret" -

info "pulling MariaDB 11 seed image: $mariadb11_image"
if ! podman image exists "$mariadb11_image"; then
  podman pull "$mariadb11_image" >/dev/null
fi

info "starting real MariaDB 11 container to seed fake data"
podman run --detach --name "$seed_container" --network none \
  --user mysql:mysql --read-only --read-only-tmpfs \
  --cap-drop all --security-opt=no-new-privileges --pids-limit 1024 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  --tmpfs /run/mysqld:rw,noexec,nosuid,nodev \
  --secret "${root_secret},type=env,target=MYSQL_ROOT_PASSWORD" \
  --env MYSQL_DATABASE=supernotedb \
  --env MYSQL_USER=supernote \
  --secret "${user_secret},type=env,target=MYSQL_PASSWORD" \
  --volume "$test_volume:/var/lib/mysql:U" \
  "$mariadb11_image" --skip-name-resolve --bind-address=0.0.0.0 >/dev/null

ready=false
for ((i = 1; i <= 90; i++)); do
  if podman exec "$seed_container" sh -c \
    'mariadb-admin ping -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
$ready || die "seed container failed to become ready: $seed_container"

info "seeding fake data into MariaDB 11 database"
podman exec -i "$seed_container" sh -c \
  'mariadb -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" supernotedb' <<'SQL'
CREATE TABLE test_notes (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  owner VARCHAR(64) NOT NULL,
  title VARCHAR(128) NOT NULL
);
INSERT INTO test_notes (owner, title) VALUES
  ('alice', 'Grocery list'),
  ('bob', 'Homelab MariaDB upgrade');
CREATE PROCEDURE count_test_notes()
  SELECT COUNT(*) FROM test_notes;
SQL

seeded_tables=$(podman exec "$seed_container" sh -c \
  'mariadb -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --batch --skip-column-names --execute="SHOW TABLES FROM supernotedb"')
seeded_tables=$(tr -d '[:space:]' <<<"$seeded_tables")
[[ $seeded_tables == *test_notes* ]] || die "seed did not create supernotedb.test_notes"

podman rm -f "$seed_container" >/dev/null

mountpoint=$(podman volume inspect --format '{{.Mountpoint}}' "$test_volume")
on_disk_version=$(podman unshare cat "$mountpoint/mariadb_upgrade_info" 2>/dev/null | tr -d '[:space:]' || true)
if [[ -z $on_disk_version ]]; then
  on_disk_version=$(podman unshare cat "$mountpoint/mysql_upgrade_info" 2>/dev/null | tr -d '[:space:]' || true)
fi
[[ $on_disk_version == 11* ]] || die "expected seeded volume MariaDB 11, got ${on_disk_version:-missing}"

info "constructing test release layout pointing to test volume"
test_release="$test_parent/release"
install -d -m 0700 "$test_release/bin" "$test_release/quadlet/applications/supernote" \
  "$test_release/quadlet/volumes"
cp "$source_root/bin/migrate-databases" "$source_root/bin/migrate-mariadb" \
  "$source_root/bin/lib.sh" "$test_release/bin/"
chmod 0755 "$test_release/bin/migrate-databases" "$test_release/bin/migrate-mariadb"

cat >"$test_release/quadlet/volumes/supernote-mariadb.volume" <<EOF
[Volume]
VolumeName=$test_volume
Label=io.containers.systemd.application=supernote
EOF

cat >"$test_release/quadlet/applications/supernote/supernote-mariadb.container" <<EOF
[Unit]
Description=Supernote MariaDB E2E Test
PartOf=homelab-supernote.target

[Container]
Image=$mariadb12_image
ContainerName=supernote-mariadb
User=mysql:mysql
Environment=MYSQL_DATABASE=supernotedb
Environment=MYSQL_USER=supernote
Secret=$root_secret,type=env,target=MYSQL_ROOT_PASSWORD
Secret=$user_secret,type=env,target=MYSQL_PASSWORD
Volume=supernote-mariadb.volume:/var/lib/mysql:U
Exec=--skip-name-resolve --bind-address=0.0.0.0
EOF

info "executing bin/migrate-mariadb on real container volume"
HOMELAB_STATE_DIR="$test_parent/state" HOMELAB_OPERATION_LOCK_HELD=1 \
  "$test_release/bin/migrate-mariadb" --release "$test_release" --workload supernote

migrated_disk_version=$(podman unshare cat "$mountpoint/mariadb_upgrade_info" 2>/dev/null | tr -d '[:space:]' || true)
[[ $migrated_disk_version == 12* ]] || die "expected migrated volume MariaDB 12, got ${migrated_disk_version:-missing}"

info "starting real MariaDB 12 container against migrated volume to verify data integrity"
podman run --detach --name "$verify_container" --network none \
  --user mysql:mysql --read-only --read-only-tmpfs \
  --cap-drop all --security-opt=no-new-privileges --pids-limit 1024 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  --tmpfs /run/mysqld:rw,noexec,nosuid,nodev \
  --secret "${root_secret},type=env,target=MYSQL_ROOT_PASSWORD" \
  --env MYSQL_DATABASE=supernotedb \
  --env MYSQL_USER=supernote \
  --volume "$test_volume:/var/lib/mysql:U" \
  "$mariadb12_image" --skip-name-resolve --bind-address=0.0.0.0 >/dev/null

ready=false
for ((i = 1; i <= 90; i++)); do
  if podman exec "$verify_container" sh -c \
    'mariadb-admin ping -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
$ready || die "verify container failed to become ready: $verify_container"

note_count=$(podman exec "$verify_container" sh -c \
  'mariadb -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --batch --skip-column-names --execute="SELECT COUNT(*) FROM supernotedb.test_notes"')
note_count=$(tr -d '[:space:]' <<<"$note_count")
[[ $note_count == "2" ]] || die "expected 2 notes, found $note_count"

note_title=$(podman exec "$verify_container" sh -c \
  'mariadb -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --batch --skip-column-names --execute="SELECT title FROM supernotedb.test_notes WHERE id = 2"')
note_title=$(tr -d '\r\n' <<<"$note_title")
[[ $note_title == "Homelab MariaDB upgrade" ]] || die "note title mismatch: $note_title"

routine_name=$(podman exec "$verify_container" sh -c \
  'mariadb -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --batch --skip-column-names --execute="SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='\''supernotedb'\'' AND ROUTINE_NAME='\''count_test_notes'\''"')
routine_name=$(tr -d '[:space:]' <<<"$routine_name")
[[ $routine_name == "count_test_notes" ]] || die "expected stored procedure count_test_notes, found ${routine_name:-missing}"

podman rm -f "$verify_container" >/dev/null

info "real container MariaDB major version upgrade E2E test passed successfully"
