#!/usr/bin/env bash
set -Eeuo pipefail

source_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck source=/dev/null
source "$source_root/bin/lib.sh"
# shellcheck source=/dev/null
source "$source_root/bin/lib-host-storage.sh"

require_command jq

fake_bin="$test_root/fake-bin"
dev="$test_root/dev"
by_id="$test_root/disk-by-id"
home="$test_root/home"
systemd_dir="$test_root/systemd"
fstab="$test_root/fstab"
lsblk_json="$test_root/lsblk.json"
blkid_db="$test_root/blkid.tsv"
mounted_flag="$test_root/mounted"
log="$test_root/commands.log"
os_source="$dev/sda2"
data_uuid=22222222-2222-2222-2222-222222222222
ext4_uuid=44444444-4444-4444-4444-444444444444
format_uuid=33333333-3333-3333-3333-333333333333
test_user=$(id -un)
storage_path="$home/.local/share/containers/storage"
failures=0

install -d "$fake_bin" "$dev" "$by_id" "$home" "$systemd_dir"

export HOMELAB_STORAGE_TEST=1
export HOMELAB_STORAGE_PATH=$storage_path
export HOMELAB_RUNTIME_HOME=$home
export HOMELAB_FSTAB=$fstab
export HOMELAB_SYSTEMD_SYSTEM_DIR=$systemd_dir
export HOMELAB_DISK_BY_ID_DIR=$by_id
export TEST_LSBLK_JSON=$lsblk_json
export TEST_BLKID_DB=$blkid_db
export TEST_MOUNTED_FLAG=$mounted_flag
export TEST_OS_SOURCE=$os_source
export TEST_LOG=$log
export TEST_FSTAB=$fstab
export TEST_STORAGE_PATH=$storage_path
export TEST_LSBLK_AFTER_SFDISK=$test_root/lsblk-after-sfdisk.json

touch "$dev/sda" "$dev/sda1" "$dev/sda2" "$dev/sdb" "$dev/sdb1" "$dev/sdc" "$dev/sdd" "$dev/sdd1"
ln -s "$dev/sdb" "$by_id/ata-DATA"
ln -s "$dev/sdb1" "$by_id/ata-DATA-part1"
ln -s "$dev/sdc" "$by_id/ata-EMPTY"
ln -s "$dev/sdd1" "$by_id/ata-EXT4-part1"

write_lsblk_json() {
  cat >"$lsblk_json" <<EOF
{
  "blockdevices": [
    {
      "name": "$dev/sda",
      "size": "476.9G",
      "model": "OS",
      "tran": "sata",
      "type": "disk",
      "fstype": null,
      "uuid": null,
      "pkname": null,
      "mountpoint": null,
      "children": [
        {
          "name": "$dev/sda1",
          "size": "1G",
          "model": "",
          "tran": "",
          "type": "part",
          "fstype": "ext4",
          "uuid": "11111111-1111-1111-1111-111111111111",
          "pkname": "$dev/sda",
          "mountpoint": "/boot"
        },
        {
          "name": "$dev/sda2",
          "size": "475G",
          "model": "",
          "tran": "",
          "type": "part",
          "fstype": "xfs",
          "uuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "pkname": "$dev/sda",
          "mountpoint": "/"
        }
      ]
    },
    {
      "name": "$dev/sdb",
      "size": "1.8T",
      "model": "ST2000",
      "tran": "sata",
      "type": "disk",
      "fstype": null,
      "uuid": null,
      "pkname": null,
      "mountpoint": null,
      "children": [
        {
          "name": "$dev/sdb1",
          "size": "1.8T",
          "model": "",
          "tran": "",
          "type": "part",
          "fstype": "xfs",
          "uuid": "$data_uuid",
          "pkname": "$dev/sdb",
          "mountpoint": null
        }
      ]
    },
    {
      "name": "$dev/sdc",
      "size": "4T",
      "model": "USB",
      "tran": "usb",
      "type": "disk",
      "fstype": null,
      "uuid": null,
      "pkname": null,
      "mountpoint": null
    },
    {
      "name": "$dev/sdd",
      "size": "500G",
      "model": "EXT4DISK",
      "tran": "sata",
      "type": "disk",
      "fstype": null,
      "uuid": null,
      "pkname": null,
      "mountpoint": null,
      "children": [
        {
          "name": "$dev/sdd1",
          "size": "500G",
          "model": "",
          "tran": "",
          "type": "part",
          "fstype": "ext4",
          "uuid": "$ext4_uuid",
          "pkname": "$dev/sdd",
          "mountpoint": null
        }
      ]
    },
    {
      "name": "$dev/loop0",
      "size": "2G",
      "model": "",
      "tran": "",
      "type": "loop",
      "fstype": "ext4",
      "uuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      "pkname": null,
      "mountpoint": null
    }
  ]
}
EOF
  cat >"$TEST_LSBLK_AFTER_SFDISK" <<EOF
{
  "blockdevices": [
    {
      "name": "$dev/sdc",
      "size": "4T",
      "model": "USB",
      "tran": "usb",
      "type": "disk",
      "fstype": null,
      "uuid": null,
      "pkname": null,
      "mountpoint": null,
      "children": [
        {
          "name": "$dev/sdc1",
          "size": "4T",
          "model": "",
          "tran": "",
          "type": "part",
          "fstype": "",
          "uuid": "",
          "pkname": "$dev/sdc",
          "mountpoint": null
        }
      ]
    }
  ]
}
EOF
}

cat >"$fake_bin/lsblk" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'lsblk %s\n' "$*" >>"${TEST_LOG}"
cat "$TEST_LSBLK_JSON"
EOF

cat >"$fake_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'findmnt %s\n' "$*" >>"${TEST_LOG}"
target=
field=
nofsroot=false
while (($#)); do
  case "$1" in
    -n) shift ;;
    -v|--nofsroot) nofsroot=true; shift ;;
    -o) field=$2; shift 2 ;;
    --target) target=$2; shift 2 ;;
    *) target=$1; shift ;;
  esac
done
if [[ $target == / || $target == /home ]]; then
  [[ $field == SOURCE || -z $field ]] || exit 1
  source=$TEST_OS_SOURCE
  if $nofsroot; then
    source=${source%%\[*}
  fi
  printf '%s\n' "$source"
  exit 0
fi
if [[ $target == "$TEST_STORAGE_PATH" && -e $TEST_MOUNTED_FLAG ]]; then
  uuid=$(awk -v marker="# homelab-podman-storage" '
    $0 == marker { getline; sub(/^UUID=/, ""); print $1; exit }
  ' "$TEST_FSTAB" 2>/dev/null || true)
  case "$field" in
    UUID) printf '%s\n' "$uuid" ;;
    SOURCE) printf '%s\n' "$(<"$TEST_MOUNTED_FLAG")" ;;
    "") printf '%s %s\n' "$(<"$TEST_MOUNTED_FLAG")" "$TEST_STORAGE_PATH" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 1
EOF

cat >"$fake_bin/blkid" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'blkid %s\n' "$*" >>"${TEST_LOG}"
key=
device=
while (($#)); do
  case "$1" in
    -s) key=$2; shift 2 ;;
    -o) shift 2 ;;
    *) device=$1; shift ;;
  esac
done
[[ -n $device && -f ${TEST_BLKID_DB} ]] || exit 1
while IFS=$'\t' read -r path uuid fstype; do
  [[ $path == "$device" ]] || continue
  case "$key" in
    UUID) printf '%s\n' "$uuid"; exit 0 ;;
    TYPE) printf '%s\n' "$fstype"; exit 0 ;;
  esac
done <"$TEST_BLKID_DB"
exit 1
EOF

cat >"$fake_bin/wipefs" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'wipefs %s\n' "$*" >>"${TEST_LOG}"
EOF

cat >"$fake_bin/sfdisk" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sfdisk %s\n' "$*" >>"${TEST_LOG}"
cat >/dev/null
cp "$TEST_LSBLK_AFTER_SFDISK" "$TEST_LSBLK_JSON"
touch "${TEST_DEV_ROOT}/sdc1"
EOF

cat >"$fake_bin/mkfs.xfs" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'mkfs.xfs %s\n' "$*" >>"${TEST_LOG}"
args=("$@")
i=0
while ((i < ${#args[@]})); do
  if [[ ${args[i]} == -L ]]; then
    i=$((i + 1))
    label=${args[i]}
    if ((${#label} > 12)); then
      printf 'Invalid value %s for -L option\n' "$label" >&2
      exit 1
    fi
  fi
  i=$((i + 1))
done
device=${!#}
printf '%s\t%s\txfs\n' "$device" "33333333-3333-3333-3333-333333333333" >>"$TEST_BLKID_DB"
EOF

cat >"$fake_bin/udevadm" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'udevadm %s\n' "$*" >>"${TEST_LOG}"
EOF

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl %s\n' "$*" >>"${TEST_LOG}"
if [[ $1 == enable && $2 == *.automount ]]; then
  printf 'generated automount units cannot be enabled\n' >&2
  exit 1
fi
if [[ $1 == start && $2 == *.mount ]]; then
  source=$(awk -v marker="# homelab-podman-storage" '
    $0 == marker { getline; print $2; exit }
  ' "$TEST_FSTAB")
  printf '%s\n' "$source" >"$TEST_MOUNTED_FLAG"
fi
EOF

cat >"$fake_bin/restorecon" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'restorecon %s\n' "$*" >>"${TEST_LOG}"
EOF

chmod 0755 "$fake_bin"/*

export PATH="$fake_bin:$PATH"
export TEST_DEV_ROOT=$dev

reset_state() {
  homelab_storage_invalidate_inventory
  write_lsblk_json
  : >"$log"
  : >"$fstab"
  rm -f -- "$mounted_flag"
  rm -rf -- "$home/.local" "$systemd_dir/user@"*
  mkdir -p "$systemd_dir"
  printf '%s\t%s\txfs\n' "$dev/sdb1" "$data_uuid" >"$blkid_db"
  printf '%s\t%s\txfs\n' "$dev/sda2" "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" >>"$blkid_db"
  printf '%s\t%s\text4\n' "$dev/sdd1" "$ext4_uuid" >>"$blkid_db"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_ok() {
  local description=$1
  shift
  if ! "$@" >/dev/null; then
    fail "$description"
    return
  fi
}

assert_fails() {
  local description=$1 rc=0
  shift
  ( set -Eeuo pipefail; "$@" ) >/dev/null 2>&1 || rc=$?
  if ((rc == 0)); then
    fail "$description (expected failure)"
  fi
}

assert_file_contains() {
  local file=$1 needle=$2 description=$3
  if ! rg -q -- "$needle" "$file"; then
    fail "$description"
  fi
}

assert_file_lacks() {
  local file=$1 needle=$2 description=$3
  if rg -q -- "$needle" "$file"; then
    fail "$description"
  fi
}

reset_state

assert_fails 'os partition cannot be used' homelab_storage_assert_not_os_device "$dev/sda2"
assert_fails 'os disk cannot be used' homelab_storage_assert_not_os_device "$dev/sda"
if homelab_storage_is_os_device "$dev/sdb1"; then
  fail 'data partition treated as OS disk'
fi
assert_fails 'apply refuses the OS disk' homelab_storage_apply "$dev/sda2" false "$test_user"

TEST_OS_SOURCE="${os_source}[/root]"
assert_fails 'btrfs root partition cannot be used' homelab_storage_assert_not_os_device "$dev/sda2"
assert_fails 'btrfs root disk cannot be used' homelab_storage_assert_not_os_device "$dev/sda"
TEST_OS_SOURCE=$os_source

mapfile -t candidates < <(homelab_storage_candidate_lines)
candidate_text=$(printf '%s\n' "${candidates[@]}")
os_disk=$(homelab_storage_canonical "$dev/sda")
[[ $candidate_text != *"$os_disk"* ]] || fail 'OS disk leaked into candidates'
[[ $candidate_text != *loop0* ]] || fail 'loop device leaked into candidates'
[[ $candidate_text == *"$(homelab_storage_canonical "$dev/sdb1")"* ]] || fail 'data partition missing from candidates'
[[ $candidate_text == *"$(homelab_storage_canonical "$dev/sdc")"* ]] || fail 'empty disk missing from candidates'

reset_state
homelab_storage_apply "$dev/sdb1" false "$test_user"
assert_file_contains "$fstab" "$HOMELAB_STORAGE_FSTAB_MARKER" 'existing xfs writes managed fstab marker'
assert_file_contains "$fstab" "UUID=$data_uuid $storage_path xfs $HOMELAB_STORAGE_FSTAB_OPTIONS 0 2" \
  'existing xfs fstab line uses UUID automount options'
assert_file_lacks "$fstab" 'nofail' 'fstab must not use nofail'
assert_file_contains "$log" 'systemctl start .*automount' 'generated automount unit is started'
assert_file_lacks "$log" 'systemctl enable' 'generated automount unit is not enabled'
uid=$(id -u "$test_user")
dropin="$systemd_dir/user@${uid}.service.d/homelab-storage.conf"
assert_file_contains "$dropin" "RequiresMountsFor=$storage_path" \
  'user unit waits for the storage mount'

reset_state
homelab_storage_apply "$dev/sdd1" false "$test_user"
assert_file_contains "$fstab" "UUID=$ext4_uuid $storage_path ext4" 'existing ext4 is accepted'

reset_state
touch "$dev/sdc1"
homelab_storage_apply "$dev/sdc" true "$test_user"
assert_file_contains "$log" 'wipefs -a' 'format wipes the selected disk'
assert_file_contains "$log" 'sfdisk --wipe always --wipe-partitions always' 'format recreates GPT'
assert_file_contains "$log" 'mkfs.xfs -f -L homelab-data' 'format creates XFS'
assert_file_contains "$fstab" "UUID=$format_uuid $storage_path xfs $HOMELAB_STORAGE_FSTAB_OPTIONS 0 2" \
  'formatted disk is recorded in fstab'

reset_state
homelab_storage_apply "$dev/sdb1" false "$test_user"
homelab_storage_setup skip '' false "$test_user"
assert_ok 'already mounted setup is idempotent' homelab_storage_already_mounted_correctly
assert_fails 'format is refused for a live storage disk' \
  homelab_storage_setup use "$dev/sdb1" true "$test_user"
assert_fails 'conflicting UUID is refused' \
  homelab_storage_setup use "$dev/sdd1" false "$test_user"

reset_state
install -d -m 0700 "$storage_path"
printf 'keep\n' >"$storage_path/existing"
assert_fails 'non-empty mountpoint is refused' homelab_storage_apply "$dev/sdb1" false "$test_user"

reset_state
printf '%s %s xfs defaults 0 2\n' "UUID=$data_uuid" "$storage_path" >"$fstab"
assert_fails 'unmanaged fstab entry is refused' \
  homelab_storage_write_fstab "$data_uuid" xfs

reset_state
answers=$test_root/answers
printf 'n\n' >"$answers"
exec 8<"$answers"
export HOMELAB_STORAGE_TTY_FD=8
if selection=$(homelab_storage_prompt 2>/dev/null); then
  fail 'declining an external disk should return 1'
fi
exec 8<&-
unset HOMELAB_STORAGE_TTY_FD

reset_state
printf '%s\n' y 999 >"$answers"
exec 8<"$answers"
export HOMELAB_STORAGE_TTY_FD=8
assert_fails 'interactive setup propagates prompt failures' \
  homelab_storage_setup auto '' false "$test_user"
exec 8<&-
unset HOMELAB_STORAGE_TTY_FD

reset_state
printf 'n\n' >"$answers"
exec 8<"$answers"
export HOMELAB_STORAGE_TTY_FD=8
assert_ok 'declining interactive storage succeeds' \
  homelab_storage_setup auto '' false "$test_user"
exec 8<&-
unset HOMELAB_STORAGE_TTY_FD

reset_state
printf '%s\n' y 1 1 'NOPE' >"$answers"
exec 8<"$answers"
export HOMELAB_STORAGE_TTY_FD=8
if (homelab_storage_prompt) >/dev/null 2>&1; then
  fail 'wrong format confirmation was accepted'
fi
exec 8<&-
unset HOMELAB_STORAGE_TTY_FD

reset_state
# Candidates are sdb, sdb1, sdc, sdd, sdd1. Select sdc (3) and format.
printf '%s\n' y 3 1 "FORMAT $by_id/ata-EMPTY" >"$answers"
exec 8<"$answers"
export HOMELAB_STORAGE_TTY_FD=8
selection=$(homelab_storage_prompt 2>/dev/null)
exec 8<&-
unset HOMELAB_STORAGE_TTY_FD
[[ $selection == "$(homelab_storage_canonical "$dev/sdc")"$'\t'true ]] || fail "format prompt selection was $selection"

reset_state
if ! (homelab_storage_setup auto '' false "$test_user"); then
  fail 'non-TTY auto mode should skip'
fi
[[ ! -s $fstab ]] || fail 'non-TTY auto mode wrote fstab'

if ((failures > 0)); then
  printf '%s bootstrap storage tests failed\n' "$failures" >&2
  exit 1
fi
printf 'bootstrap storage tests passed\n'
