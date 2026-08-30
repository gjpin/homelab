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

pg17_image="docker.io/postgres:17.10-bookworm@sha256:9b18b78397054fce88a9552e9d5a3ad5bb7fd258c5b3cc1c5028e46373d6ea8f"
if [[ -f "$source_root/config/legacy-migration.env" ]]; then
  configured_pg17=$(sed -n 's/^LEGACY_FORGEJO_POSTGRES_IMAGE=//p' "$source_root/config/legacy-migration.env")
  [[ -n $configured_pg17 ]] && pg17_image="$configured_pg17"
fi

target_unit="$source_root/quadlet/applications/forgejo/forgejo-postgres.container"
[[ -f $target_unit ]] || die "target unit not found: $target_unit"
pg18_image=$(sed -n 's/^Image=//p' "$target_unit")
[[ -n $pg18_image ]] || die "missing Image in $target_unit"

test_parent=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/homelab-pg-e2e.XXXXXX")
test_volume="homelab-e2e-migrate-$$-$(date +%s)"
seed_container="homelab-e2e-seed-$$"
verify_container="homelab-e2e-verify-$$"
install -d -m 0700 "$test_parent/runtime"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$test_parent/runtime}"

cleanup() {
  local rc=$?
  set +e
  podman rm -f "$seed_container" "$verify_container" >/dev/null 2>&1 || true
  podman volume rm -f "$test_volume" >/dev/null 2>&1 || true
  rm -rf -- "$test_parent"
  trap - EXIT
  exit "$rc"
}
trap cleanup EXIT

info "creating real Podman test volume: $test_volume"
podman volume create --label io.containers.systemd.application=forgejo "$test_volume" >/dev/null

info "pulling PostgreSQL 17 seed image: $pg17_image"
if ! podman image exists "$pg17_image"; then
  podman pull "$pg17_image" >/dev/null
fi

info "starting real PostgreSQL 17 container to seed fake data"
podman run --detach --name "$seed_container" --network none \
  --user postgres:postgres --read-only --read-only-tmpfs \
  --cap-drop all --security-opt=no-new-privileges --pids-limit 1024 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  --tmpfs /run/postgresql:rw,noexec,nosuid,nodev \
  --tmpfs /var/run/postgresql:rw,noexec,nosuid,nodev \
  --env POSTGRES_USER=forgejo \
  --env POSTGRES_DB=forgejo \
  --env PGDATA=/var/lib/postgresql/data \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  --volume "$test_volume:/var/lib/postgresql/data:U" \
  "$pg17_image" >/dev/null

# Wait for seed container readiness
ready=false
for ((i = 1; i <= 90; i++)); do
  if podman exec "$seed_container" pg_isready -h 127.0.0.1 -U forgejo -d forgejo >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
$ready || die "seed container failed to become ready: $seed_container"

info "seeding fake data into PostgreSQL 17 database"
podman exec "$seed_container" psql -h 127.0.0.1 -U forgejo -d forgejo --command="
  CREATE TABLE test_repositories (
    id SERIAL PRIMARY KEY,
    owner TEXT NOT NULL,
    name TEXT NOT NULL,
    num_stars INTEGER DEFAULT 0
  );
  INSERT INTO test_repositories (owner, name, num_stars) VALUES
    ('alice', 'dotfiles', 42),
    ('bob', 'homelab-config', 108);

  CREATE TABLE test_issues (
    id SERIAL PRIMARY KEY,
    repo_id INTEGER REFERENCES test_repositories(id),
    title TEXT NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE
  );
  INSERT INTO test_issues (repo_id, title, is_closed) VALUES
    (1, 'Add zsh config', true),
    (2, 'Automate postgres major upgrades', false);
" >/dev/null

podman rm -f "$seed_container" >/dev/null

mountpoint=$(podman volume inspect --format '{{.Mountpoint}}' "$test_volume")
on_disk_version=$(podman unshare cat "$mountpoint/PG_VERSION" | tr -d '[:space:]')
[[ $on_disk_version == "17" ]] || die "expected seeded volume PG_VERSION to be 17, got $on_disk_version"

info "constructing test release layout pointing to test volume"
test_release="$test_parent/release"
install -d -m 0700 "$test_release/bin" "$test_release/quadlet/applications/forgejo" "$test_release/quadlet/volumes"
cp "$source_root/bin/migrate-databases" "$source_root/bin/migrate-postgres" \
  "$source_root/bin/lib.sh" "$test_release/bin/"
chmod 0755 "$test_release/bin/migrate-databases" "$test_release/bin/migrate-postgres"

cat >"$test_release/quadlet/volumes/forgejo-postgres.volume" <<EOF
[Volume]
VolumeName=$test_volume
Label=io.containers.systemd.application=forgejo
EOF

cat >"$test_release/quadlet/applications/forgejo/forgejo-postgres.container" <<EOF
[Unit]
Description=Forgejo PostgreSQL E2E Test
PartOf=homelab-forgejo.target

[Container]
Image=$pg18_image
ContainerName=forgejo-postgres
User=postgres:postgres
Network=forgejo.network
Environment=POSTGRES_USER=forgejo
Environment=POSTGRES_DB=forgejo
Environment=PGDATA=/var/lib/postgresql/data
Volume=forgejo-postgres.volume:/var/lib/postgresql/data:U
EOF

info "executing bin/migrate-postgres on real container volume"
HOMELAB_STATE_DIR="$test_parent/state" HOMELAB_OPERATION_LOCK_HELD=1 \
  "$test_release/bin/migrate-postgres" --release "$test_release" --workload forgejo

migrated_disk_version=$(podman unshare cat "$mountpoint/PG_VERSION" | tr -d '[:space:]')
[[ $migrated_disk_version == "18" ]] || die "expected migrated volume PG_VERSION to be 18, got $migrated_disk_version"

info "starting real PostgreSQL 18 container against migrated volume to verify data integrity"
podman run --detach --name "$verify_container" --network none \
  --user postgres:postgres --read-only --read-only-tmpfs \
  --cap-drop all --security-opt=no-new-privileges --pids-limit 1024 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  --tmpfs /run/postgresql:rw,noexec,nosuid,nodev \
  --tmpfs /var/run/postgresql:rw,noexec,nosuid,nodev \
  --env POSTGRES_USER=forgejo \
  --env POSTGRES_DB=forgejo \
  --env PGDATA=/var/lib/postgresql/data \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  --volume "$test_volume:/var/lib/postgresql/data:U" \
  "$pg18_image" >/dev/null

ready=false
for ((i = 1; i <= 90; i++)); do
  if podman exec "$verify_container" pg_isready -h 127.0.0.1 -U forgejo -d forgejo >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
$ready || die "verify container failed to become ready: $verify_container"

# Query seeded data in new PG 18 container
repo_count=$(podman exec "$verify_container" psql -h 127.0.0.1 -U forgejo -d forgejo \
  --tuples-only --no-align --command="SELECT count(*) FROM test_repositories;")
[[ $repo_count == "2" ]] || die "expected 2 repositories, found $repo_count"

issue_title=$(podman exec "$verify_container" psql -h 127.0.0.1 -U forgejo -d forgejo \
  --tuples-only --no-align --command="SELECT title FROM test_issues WHERE id = 2;")
[[ $issue_title == "Automate postgres major upgrades" ]] || die "issue title mismatch: $issue_title"

podman rm -f "$verify_container" >/dev/null

info "real container PostgreSQL major version upgrade E2E test passed successfully"
