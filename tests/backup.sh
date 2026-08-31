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

install -d "$fixture/bin" "$fixture/secrets" "$fixture/manifests" \
  "$fixture/quadlet" "$fake_bin" "$runtime_dir" \
  "$test_home/.config/sops/age" "$state_dir"
cp "$source_root/bin/backup" "$source_root/bin/lib.sh" "$fixture/bin/"
cp "$source_root/manifests/applications.json" "$fixture/manifests/"
cp -R "$source_root/quadlet/volumes" "$fixture/quadlet/"

printf '{}\n' >"$fixture/secrets/secrets.sops.yaml"
printf 'AGE-SECRET-KEY-TEST\n' >"$test_home/.config/sops/age/keys.txt"
printf '0123456789abcdef0123456789abcdef01234567\n' >"$state_dir/deployed-commit"
cat >"$fixture/bin/restic" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'restic %s\n' "$*" >>"$TEST_LOG"
case "${1:-}" in
  cat|forget|check) exit 0 ;;
  backup)
    [[ ${TEST_BACKUP_FAIL:-0} != 1 ]] || exit 12
    printf '{"message_type":"summary","snapshot_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n'
    [[ ${TEST_BACKUP_INCOMPLETE:-0} != 1 ]] || exit 3
    ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == --user ]] && shift
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
case "${1:-}" in
  is-active) exit 0 ;;
  show) exit 0 ;;
  start|stop|disable) exit 0 ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/podman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'podman %s\n' "$*" >>"$TEST_LOG"
case "${1:-} ${2:-}" in
  'volume ls')
    sed -n 's/^VolumeName=//p' "$TEST_FIXTURE"/quadlet/volumes/*.volume | sort |
      if [[ ${TEST_VOLUME_MISMATCH:-0} == 1 ]]; then sed '$d'; else cat; fi
    if [[ ${TEST_INCUBATOR_VOLUME:-0} == 1 && "$*" != *'label=io.containers.systemd.application='* ]]; then
      printf 'homelab-incubator-preserved-volume\n'
    fi
    ;;
  'volume inspect')
    volume=${!#}
    mountpoint="$TEST_VOLUME_ROOT/$volume"
    install -d "$mountpoint"
    printf '%s\n' "$mountpoint"
    ;;
  'ps --quiet') exit 0 ;;
  unshare\ *) shift; exec "$@" ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/flock" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'flock %s\n' "$*" >>"$TEST_LOG"
[[ ${TEST_LOCK_FAIL:-0} != 1 ]]
EOF

cat >"$fake_bin/date" <<'EOF'
#!/usr/bin/env bash
printf '2026-08-28T03:00:00Z\n'
EOF

cat >"$fake_bin/sops" <<'EOF'
#!/usr/bin/env bash
jq -n --arg prefix "${TEST_S3_PREFIX-homelab}" '{
  site: {
    base_domain: "home.example.com",
    timezone: "Europe/Lisbon",
    homeassistant_zigbee_router_serial_id: "test-device"
  },
  backup: {
    s3_endpoint: "https://s3.example.com",
    s3_region: "us-east-1",
    s3_bucket: "homelab-test",
    s3_prefix: $prefix,
    s3_access_key_id: "id",
    s3_secret_access_key: "key",
    repository_password: "passwordpasswordpassword"
  }
}'
EOF

chmod 0755 "$fixture/bin/backup" "$fixture/bin/restic" \
  "$fake_bin/systemctl" "$fake_bin/podman" "$fake_bin/flock" "$fake_bin/date" \
  "$fake_bin/sops"

run_backup() {
  env PATH="$fake_bin:$PATH" HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" \
    HOMELAB_STATE_DIR="$state_dir" TEST_LOG="$log" TEST_FIXTURE="$fixture" \
    TEST_VOLUME_ROOT="$test_root/volumes" \
    TEST_BACKUP_FAIL="${TEST_BACKUP_FAIL:-0}" \
    TEST_BACKUP_INCOMPLETE="${TEST_BACKUP_INCOMPLETE:-0}" \
    TEST_VOLUME_MISMATCH="${TEST_VOLUME_MISMATCH:-0}" \
    TEST_LOCK_FAIL="${TEST_LOCK_FAIL:-0}" \
    TEST_INCUBATOR_VOLUME="${TEST_INCUBATOR_VOLUME:-0}" \
    "$fixture/bin/backup" "$@"
}

: >"$log"
TEST_INCUBATOR_VOLUME=1 run_backup --tag automatic >/dev/null
rg -q '^restic backup .*--tag homelab --tag automatic --json$' "$log"
rg -q '^restic forget .*--keep-daily 2 --keep-weekly 4 --keep-monthly 2 --prune$' "$log"
rg -q '^restic check$' "$log"
rg -q '^systemctl stop homelab-reconcile.timer homelab-backup.timer$' "$log"
rg -q '^systemctl start homelab.target$' "$log"
rg -q '^systemctl start homelab-reconcile.timer$' "$log"
rg -q '^systemctl start homelab-backup.timer$' "$log"

: >"$log"
if TEST_BACKUP_FAIL=1 run_backup --tag automatic >/dev/null 2>&1; then
  printf 'backup failure injection unexpectedly succeeded\n' >&2
  exit 1
fi
rg -q '^systemctl start homelab.target$' "$log"
rg -q '^systemctl start homelab-reconcile.timer$' "$log"
rg -q '^systemctl start homelab-backup.timer$' "$log"
if rg -q '^restic forget ' "$log"; then
  printf 'retention ran after a failed snapshot\n' >&2
  exit 1
fi

: >"$log"
if TEST_BACKUP_INCOMPLETE=1 run_backup --tag automatic >/dev/null 2>&1; then
  printf 'incomplete restic snapshot unexpectedly succeeded\n' >&2
  exit 1
fi
rg -q '^restic forget aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$' "$log"
rg -q '^systemctl start homelab.target$' "$log"
[[ ! -e $state_dir/incomplete-backup-snapshot ]]

: >"$log"
printf '%s\n' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  >"$state_dir/incomplete-backup-snapshot"
run_backup --tag automatic >/dev/null
rg -q '^restic forget bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb$' "$log"
[[ ! -e $state_dir/incomplete-backup-snapshot ]]

: >"$log"
run_backup --tag migration --leave-stopped-on-success >/dev/null
rg -q '^restic backup .*--tag homelab --tag migration --json$' "$log"
rg -q '^systemctl disable homelab-reconcile.timer homelab-backup.timer$' "$log"
if rg -q '^systemctl start ' "$log"; then
  printf 'migration backup restarted services after success\n' >&2
  exit 1
fi

: >"$log"
if TEST_VOLUME_MISMATCH=1 run_backup --tag automatic >/dev/null 2>&1; then
  printf 'volume inventory mismatch unexpectedly succeeded\n' >&2
  exit 1
fi
if rg -q '^systemctl stop ' "$log"; then
  printf 'preflight failure stopped services\n' >&2
  exit 1
fi

: >"$log"
if TEST_LOCK_FAIL=1 run_backup --tag automatic >/dev/null 2>&1; then
  printf 'maintenance lock collision unexpectedly succeeded\n' >&2
  exit 1
fi
if rg -q '^(restic|systemctl|podman) ' "$log"; then
  printf 'maintenance lock collision performed backup work\n' >&2
  exit 1
fi

printf 'backup orchestration tests passed\n'

restic_root="$test_root/restic-wrapper"
install -d "$restic_root/bin" "$restic_root/secrets"
cp "$source_root/bin/restic" "$source_root/bin/lib.sh" "$restic_root/bin/"
chmod 0755 "$restic_root/bin/restic"
printf '{}\n' >"$restic_root/secrets/secrets.sops.yaml"

cat >"$fake_bin/print-restic-repository" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${RESTIC_REPOSITORY-}"
EOF
chmod 0755 "$fake_bin/print-restic-repository"

run_restic_wrapper() {
  env PATH="$fake_bin:$PATH" HOMELAB_RESTIC_BIN="$fake_bin/print-restic-repository" \
    TEST_S3_PREFIX="${1-}" \
    "$restic_root/bin/restic"
}

# shellcheck source=/dev/null
source "$source_root/bin/lib.sh"

assert_prefix_rejected() {
  local prefix=$1
  if (validate_backup_s3_prefix "$prefix") >/dev/null 2>&1; then
    printf 'backup.s3_prefix=%s unexpectedly accepted\n' "$prefix" >&2
    exit 1
  fi
}

validate_backup_s3_prefix ''
[[ $(run_restic_wrapper '') == 's3:https://s3.example.com/homelab-test' ]] || {
  printf 'empty prefix produced an unexpected restic repository URL\n' >&2
  exit 1
}

validate_backup_s3_prefix homelab
[[ $(run_restic_wrapper homelab) == 's3:https://s3.example.com/homelab-test/homelab' ]] || {
  printf 'prefixed repository URL is incorrect\n' >&2
  exit 1
}

assert_prefix_rejected '..'
assert_prefix_rejected 'foo//bar'
assert_prefix_rejected '/leading'
assert_prefix_rejected 'trailing/'
assert_prefix_rejected 'bad prefix'

printf 'restic repository prefix tests passed\n'
