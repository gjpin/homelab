#!/usr/bin/env bash
set -Eeuo pipefail

source_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fixture="$test_root/repository"
fake_bin="$test_root/fake-bin"
test_home="$test_root/home"
runtime_dir="$test_root/runtime"
state_dir="$test_home/.local/state/homelab"
log="$test_root/commands.log"

install -d "$fixture/bin" "$fixture/manifests" \
  "$fixture/quadlet/applications/forgejo" "$fixture/quadlet/applications/immich" \
  "$fixture/quadlet/volumes" "$fake_bin" "$runtime_dir" \
  "$test_home/.config/sops/age" "$state_dir"

cp "$source_root/bin/migrate-databases" "$source_root/bin/migrate-postgres" \
  "$source_root/bin/lib.sh" "$fixture/bin/"
cp "$source_root/manifests/applications.json" "$fixture/manifests/"
cp -R "$source_root/quadlet/volumes" "$fixture/quadlet/"
cp "$source_root/quadlet/applications/forgejo/forgejo-postgres.container" "$fixture/quadlet/applications/forgejo/"
cp "$source_root/quadlet/applications/immich/immich-postgres.container" "$fixture/quadlet/applications/immich/"

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == --user ]] && shift
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
case "${1:-}" in
  is-active)
    if [[ ${TEST_STOP_FAIL:-0} == 1 ]]; then
      exit 0
    fi
    exit 1
    ;;
  show|start|stop|disable|status) exit 0 ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    --acls|--xattrs|--selinux|--numeric-owner) ;;
    *) args+=("$arg") ;;
  esac
done
exec /usr/bin/tar "${args[@]}"
EOF

cat >"$fake_bin/podman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'podman %s\n' "$*" >>"$TEST_LOG"

case "${1:-} ${2:-}" in
  'volume exists')
    vol="${3:-}"
    [[ -d "$TEST_VOLUME_ROOT/$vol" ]] && exit 0
    exit 1
    ;;
  'volume inspect')
    vol="${!#}"
    mountpoint="$TEST_VOLUME_ROOT/$vol"
    install -d "$mountpoint"
    printf '%s\n' "$mountpoint"
    ;;
  'image exists')
    exit 0
    ;;
  'ps '*)
    if [[ ${TEST_VOLUME_BUSY:-0} == 1 ]]; then
      printf 'busy-container\n'
    fi
    exit 0
    ;;
  'pull '*)
    exit 0
    ;;
  'rm '*)
    exit 0
    ;;
  'cp '*)
    exit 0
    ;;
  unshare\ *)
    shift
    exec "$@"
    ;;
  'run '*)
    # Check if this is a version query
    if [[ "$*" == *'--entrypoint postgres'*'--version'* ]]; then
      if [[ "$*" == *'postgres:19'* ]]; then
        printf 'postgres (PostgreSQL) 19.1 (Debian 19.1-1.pgdg120+1)\n'
      elif [[ "$*" == *'postgres:18'* ]]; then
        printf 'postgres (PostgreSQL) 18.6 (Debian 18.6-1.pgdg120+1)\n'
      elif [[ "$*" == *'postgres:17'* ]]; then
        printf 'postgres (PostgreSQL) 17.4 (Debian 17.4-1.pgdg120+1)\n'
      else
        printf 'postgres (PostgreSQL) 18.6\n'
      fi
      exit 0
    fi

    # Check if container startup should fail
    if [[ ${TEST_START_FAIL:-0} == 1 ]]; then
      exit 1
    fi
    exit 0
    ;;
  'exec '*)
    container="$2"
    shift 2
    if [[ "$*" == *'pg_isready'* ]]; then
      exit 0
    elif [[ "$*" == *'pg_dump'* ]]; then
      if [[ ${TEST_DUMP_FAIL:-0} == 1 ]]; then
        exit 1
      fi
      printf 'MOCK_PG_DUMP_DATA\n'
      exit 0
    elif [[ "$*" == *'pg_restore'* ]]; then
      if [[ ${TEST_RESTORE_FAIL:-0} == 1 ]]; then
        exit 1
      fi
      # Simulate pg_restore writing new PG_VERSION
      target_vol="homelab-forgejo-postgres"
      [[ "$container" == *immich* ]] && target_vol="homelab-immich-postgres"
      if [[ -d "$TEST_VOLUME_ROOT/$target_vol" ]]; then
        printf '%s\n' "${TEST_NEW_VERSION:-18}" > "$TEST_VOLUME_ROOT/$target_vol/PG_VERSION"
      fi
      exit 0
    elif [[ "$*" == *'psql'* && "$*" == *'SELECT current_database()'* ]]; then
      if [[ "$container" == *immich* ]]; then
        printf 'immich\n'
      else
        printf 'forgejo\n'
      fi
      exit 0
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF

chmod 0755 "$fixture/bin/migrate-databases" "$fixture/bin/migrate-postgres" \
  "$fake_bin/systemctl" "$fake_bin/podman" "$fake_bin/tar"

run_migrate() {
  env PATH="$fake_bin:$PATH" HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" \
    HOMELAB_STATE_DIR="$state_dir" HOMELAB_OPERATION_LOCK_HELD=1 \
    TEST_LOG="$log" TEST_FIXTURE="$fixture" \
    TEST_VOLUME_ROOT="$test_root/volumes" \
    TEST_START_FAIL="${TEST_START_FAIL:-0}" \
    TEST_DUMP_FAIL="${TEST_DUMP_FAIL:-0}" \
    TEST_RESTORE_FAIL="${TEST_RESTORE_FAIL:-0}" \
    TEST_STOP_FAIL="${TEST_STOP_FAIL:-0}" \
    TEST_VOLUME_BUSY="${TEST_VOLUME_BUSY:-0}" \
    TEST_NEW_VERSION="${TEST_NEW_VERSION:-18}" \
    "$fixture/bin/migrate-postgres" "$@"
}

# Test 1: Empty volumes (no PG_VERSION) -> No migration needed
install -d "$test_root/volumes/homelab-forgejo-postgres" "$test_root/volumes/homelab-immich-postgres"
: >"$log"
run_migrate --release "$fixture"
! grep -q 'pg_dump' "$log" || exit 1

# Test 2: Versions match (PG_VERSION=18, Image is postgres:18) -> No migration needed
printf '18\n' >"$test_root/volumes/homelab-forgejo-postgres/PG_VERSION"
printf '18\n' >"$test_root/volumes/homelab-immich-postgres/PG_VERSION"
: >"$log"
run_migrate --release "$fixture"
! grep -q 'pg_dump' "$log" || exit 1

# Test 3: Check-only mode when versions match
run_migrate --release "$fixture" --check

# Test 4: Major version upgrade needed (Forgejo PG_VERSION=17, Image is postgres:18)
printf '17\n' >"$test_root/volumes/homelab-forgejo-postgres/PG_VERSION"
printf '18\n' >"$test_root/volumes/homelab-immich-postgres/PG_VERSION"

# Test 4a: Check-only mode exits 1 when migration is needed
if run_migrate --release "$fixture" --check; then
  printf 'check-only mode unexpectedly succeeded when migration was needed\n' >&2
  exit 1
fi

# Test 4b: Dry-run mode reports plan without modifying volume
: >"$log"
dry_out=$(run_migrate --release "$fixture" --dry-run 2>&1)
grep -q 'would migrate forgejo from PostgreSQL 17 to 18' <<<"$dry_out" || {
  printf 'dry-run did not log migration plan: %s\n' "$dry_out" >&2
  exit 1
}
! grep -q 'pg_dump' "$log" || exit 1
[[ $(cat "$test_root/volumes/homelab-forgejo-postgres/PG_VERSION") == '17' ]]

# Test 4c: Execute actual migration for Forgejo (17 -> 18)
: >"$log"
TEST_NEW_VERSION=18 run_migrate --release "$fixture" --workload forgejo
grep -q 'pg_dump' "$log"
grep -q 'pg_restore' "$log"
grep -q 'SELECT current_database()' "$log"
[[ $(cat "$test_root/volumes/homelab-forgejo-postgres/PG_VERSION") == '18' ]]
# Verify dump archive created in state dir and the bulky raw tar was removed
ls "$state_dir/postgres-upgrades"/forgejo-pg17-to-pg18-*.dump >/dev/null
shopt -s nullglob
raw_tars=("$state_dir/postgres-upgrades"/forgejo-postgres17-raw-*.tar)
((${#raw_tars[@]} == 0)) || {
  printf 'raw rollback tar was not removed after success\n' >&2
  exit 1
}

# Test 5: Major version upgrade for Immich (e.g. 18 -> 19)
sed -i.bak 's/postgres:18-/postgres:19-/' "$fixture/quadlet/applications/immich/immich-postgres.container"
printf '18\n' >"$test_root/volumes/homelab-immich-postgres/PG_VERSION"
: >"$log"
TEST_NEW_VERSION=19 run_migrate --release "$fixture" --workload immich
grep -q 'immich.*pg_dump' "$log"
grep -q 'immich.*pg_restore' "$log"
[[ $(cat "$test_root/volumes/homelab-immich-postgres/PG_VERSION") == '19' ]]
ls "$state_dir/postgres-upgrades"/immich-pg18-to-pg19-*.dump >/dev/null

# Test 6: Refusal of unsupported downgrade (PG_VERSION=19, Image is 18)
printf '19\n' >"$test_root/volumes/homelab-forgejo-postgres/PG_VERSION"
if run_migrate --release "$fixture" --workload forgejo >/dev/null 2>&1; then
  printf 'PostgreSQL downgrade unexpectedly succeeded\n' >&2
  exit 1
fi

# Test 7: Rollback on restore failure
printf '17\n' >"$test_root/volumes/homelab-forgejo-postgres/PG_VERSION"
printf 'original_data_file\n' >"$test_root/volumes/homelab-forgejo-postgres/original.txt"
if TEST_RESTORE_FAIL=1 run_migrate --release "$fixture" --workload forgejo >/dev/null 2>&1; then
  printf 'migration with failing restore unexpectedly succeeded\n' >&2
  exit 1
fi
# Verify original files were restored via rollback
[[ -f "$test_root/volumes/homelab-forgejo-postgres/original.txt" ]]
[[ $(cat "$test_root/volumes/homelab-forgejo-postgres/PG_VERSION") == '17' ]]
ls "$state_dir/postgres-upgrades"/forgejo-pg17-to-pg18-*.dump >/dev/null
ls "$state_dir/postgres-upgrades"/forgejo-postgres17-raw-*.tar >/dev/null

# Test 8: Refuse to migrate while the workload is still active
printf '17\n' >"$test_root/volumes/homelab-forgejo-postgres/PG_VERSION"
: >"$log"
if TEST_STOP_FAIL=1 run_migrate --release "$fixture" --workload forgejo >/dev/null 2>&1; then
  printf 'migration unexpectedly succeeded while the workload was active\n' >&2
  exit 1
fi
! grep -q 'pg_dump' "$log" || {
  printf 'dump ran while the workload was still active\n' >&2
  exit 1
}

# Test 9: Refuse to migrate while the volume is still mounted
: >"$log"
if TEST_VOLUME_BUSY=1 run_migrate --release "$fixture" --workload forgejo >/dev/null 2>&1; then
  printf 'migration unexpectedly succeeded while the volume was mounted\n' >&2
  exit 1
fi
! grep -q 'pg_dump' "$log" || {
  printf 'dump ran while the volume was still mounted\n' >&2
  exit 1
}

printf 'PostgreSQL migration orchestration tests passed\n'
