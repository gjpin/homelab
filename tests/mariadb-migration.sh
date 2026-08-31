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

install -d "$fixture/bin" "$fixture/config" "$fixture/manifests" \
  "$fixture/quadlet/applications/supernote" \
  "$fixture/quadlet/volumes" "$fake_bin" "$runtime_dir" \
  "$test_home/.config/sops/age" "$state_dir"

cp "$source_root/bin/migrate-databases" "$source_root/bin/migrate-mariadb" \
  "$source_root/bin/lib.sh" "$fixture/bin/"
cp "$source_root/manifests/applications.json" "$fixture/manifests/"
cp "$source_root/quadlet/volumes/supernote-mariadb.volume" "$fixture/quadlet/volumes/"
cp "$source_root/quadlet/applications/supernote/supernote-mariadb.container" \
  "$fixture/quadlet/applications/supernote/"

cat >"$fixture/config/site.env" <<'EOF'
BASE_DOMAIN=home.example.com
TIMEZONE=Europe/Lisbon
HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID=test-device
BACKUP_S3_ENDPOINT=https://s3.example.com
BACKUP_S3_REGION=us-east-1
BACKUP_S3_BUCKET=homelab-test
BACKUP_S3_PREFIX=homelab
EOF

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
    if [[ "$*" == *'--entrypoint mariadbd'*'--version'* ]]; then
      if [[ "$*" == *'mariadb:12'* ]]; then
        printf 'mariadbd  Ver 12.3.3-MariaDB\n'
      elif [[ "$*" == *'mariadb:11'* ]]; then
        printf 'mariadbd  Ver 11.8.2-MariaDB\n'
      else
        printf 'mariadbd  Ver 12.3.3-MariaDB\n'
      fi
      exit 0
    fi
    if [[ ${TEST_START_FAIL:-0} == 1 ]]; then
      exit 1
    fi
    exit 0
    ;;
  'exec '*)
    container="$2"
    shift 2
    if [[ "$*" == *'mariadb-admin ping'* ]]; then
      exit 0
    elif [[ "$*" == *'mariadb-dump'* ]]; then
      if [[ ${TEST_DUMP_FAIL:-0} == 1 ]]; then
        exit 1
      fi
      printf 'MOCK_MARIADB_DUMP\n'
      exit 0
    elif [[ "$*" == *'migration.sql'* ]]; then
      if [[ ${TEST_RESTORE_FAIL:-0} == 1 ]]; then
        exit 1
      fi
      target_vol="homelab-supernote-mariadb"
      if [[ -d "$TEST_VOLUME_ROOT/$target_vol" ]]; then
        printf '%s\n' "${TEST_NEW_VERSION:-12}.3.3-MariaDB" \
          >"$TEST_VOLUME_ROOT/$target_vol/mariadb_upgrade_info"
      fi
      exit 0
    elif [[ "$*" == *'SCHEMA_NAME'* ]]; then
      printf 'supernotedb\n'
      exit 0
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF

chmod 0755 "$fixture/bin/migrate-databases" "$fixture/bin/migrate-mariadb" \
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
    TEST_NEW_VERSION="${TEST_NEW_VERSION:-12}" \
    "$fixture/bin/migrate-mariadb" "$@"
}

install -d "$test_root/volumes/homelab-supernote-mariadb"

# Empty volume -> no migration
: >"$log"
run_migrate --release "$fixture"
! grep -q 'mariadb-dump' "$log" || exit 1

# Matching majors -> no migration
printf '12.3.3-MariaDB\n' >"$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info"
: >"$log"
run_migrate --release "$fixture"
! grep -q 'mariadb-dump' "$log" || exit 1
run_migrate --release "$fixture" --check

# Upgrade 11 -> 12
printf '11.8.2-MariaDB\n' >"$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info"
if run_migrate --release "$fixture" --check; then
  printf 'check-only mode unexpectedly succeeded when migration was needed\n' >&2
  exit 1
fi

: >"$log"
dry_out=$(run_migrate --release "$fixture" --dry-run 2>&1)
grep -q 'would migrate supernote from MariaDB 11 to 12' <<<"$dry_out" || {
  printf 'dry-run did not log migration plan: %s\n' "$dry_out" >&2
  exit 1
}
! grep -q 'mariadb-dump' "$log" || exit 1
[[ $(cat "$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info") == '11.8.2-MariaDB' ]]

: >"$log"
TEST_NEW_VERSION=12 run_migrate --release "$fixture" --workload supernote
grep -q 'mariadb-dump' "$log"
grep -q -- '--system=users' "$log"
grep -q -- '--ignore-database=mysql' "$log"
grep -q -- '--ignore-database=sys' "$log"
grep -q 'migration.sql' "$log"
grep -q 'SCHEMA_NAME' "$log"
[[ $(cat "$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info") == 12.3.3-MariaDB ]]
ls "$state_dir/mariadb-upgrades"/supernote-mariadb11-to-mariadb12-*.sql >/dev/null
shopt -s nullglob
raw_tars=("$state_dir/mariadb-upgrades"/supernote-mariadb11-raw-*.tar)
((${#raw_tars[@]} == 0)) || {
  printf 'raw rollback tar was not removed after success\n' >&2
  exit 1
}

# Downgrade refused
printf '13.0.0-MariaDB\n' >"$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info"
if run_migrate --release "$fixture" --workload supernote >/dev/null 2>&1; then
  printf 'MariaDB downgrade unexpectedly succeeded\n' >&2
  exit 1
fi

# Rollback on restore failure
printf '11.8.2-MariaDB\n' >"$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info"
printf 'original_data_file\n' >"$test_root/volumes/homelab-supernote-mariadb/original.txt"
if TEST_RESTORE_FAIL=1 run_migrate --release "$fixture" --workload supernote >/dev/null 2>&1; then
  printf 'migration with failing restore unexpectedly succeeded\n' >&2
  exit 1
fi
[[ -f "$test_root/volumes/homelab-supernote-mariadb/original.txt" ]]
[[ $(cat "$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info") == '11.8.2-MariaDB' ]]
ls "$state_dir/mariadb-upgrades"/supernote-mariadb11-to-mariadb12-*.sql >/dev/null
ls "$state_dir/mariadb-upgrades"/supernote-mariadb11-raw-*.tar >/dev/null

printf '11.8.2-MariaDB\n' >"$test_root/volumes/homelab-supernote-mariadb/mariadb_upgrade_info"
: >"$log"
if TEST_STOP_FAIL=1 run_migrate --release "$fixture" --workload supernote >/dev/null 2>&1; then
  printf 'migration unexpectedly succeeded while the workload was active\n' >&2
  exit 1
fi
! grep -q 'mariadb-dump' "$log" || exit 1

: >"$log"
if TEST_VOLUME_BUSY=1 run_migrate --release "$fixture" --workload supernote >/dev/null 2>&1; then
  printf 'migration unexpectedly succeeded while the volume was mounted\n' >&2
  exit 1
fi
! grep -q 'mariadb-dump' "$log" || exit 1

printf 'MariaDB migration orchestration tests passed\n'
