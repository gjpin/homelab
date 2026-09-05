#!/usr/bin/env bash
# Host-root helpers for the isolated Forgejo Actions runtime.

FORGEJO_RUNNER_STORAGE_BYTES=$((20 * 1024 * 1024 * 1024))
FORGEJO_RUNNER_STORAGE_SIZE=20G
FORGEJO_RUNNER_STORAGE_IMAGE=/var/lib/homelab/forgejo-runner-storage.xfs
FORGEJO_RUNNER_STORAGE_MARKER='# forgejo-runner-podman-storage'
FORGEJO_RUNNER_MEMORY_MAX=16G
FORGEJO_RUNNER_CPU_QUOTA=400%
FORGEJO_RUNNER_TASKS_MAX=2048

forgejo_runner_storage_path() {
  local runner_home=${1:-/home/forgejo-runner}
  printf '%s\n' "$runner_home/.local/share/containers/storage"
}

forgejo_runner_configure_storage() {
  local runner_user=$1 runner_home=$2 storage_path fstab_tmp image_size expected_line loop_device mounted_source
  storage_path=$(forgejo_runner_storage_path "$runner_home")
  for command in findmnt losetup mkfs.xfs mount truncate; do
    require_command "$command"
  done

  install -d -m 0755 /var/lib/homelab
  if [[ ! -e /etc/fstab ]]; then
    install -m 0644 /dev/null /etc/fstab
  fi
  if [[ ! -f $FORGEJO_RUNNER_STORAGE_IMAGE ]]; then
    truncate --size "$FORGEJO_RUNNER_STORAGE_SIZE" "$FORGEJO_RUNNER_STORAGE_IMAGE"
    mkfs.xfs -q -f "$FORGEJO_RUNNER_STORAGE_IMAGE"
    chmod 0600 "$FORGEJO_RUNNER_STORAGE_IMAGE"
  fi
  image_size=$(stat -c %s "$FORGEJO_RUNNER_STORAGE_IMAGE")
  [[ $image_size == "$FORGEJO_RUNNER_STORAGE_BYTES" ]] || \
    die "Forgejo Runner storage image has unexpected capacity: $image_size bytes"

  install -d -m 0700 -o "$runner_user" -g "$runner_user" \
    "$runner_home/.local" "$runner_home/.local/share" \
    "$runner_home/.local/share/containers" "$storage_path"
  if ! grep -Fxq "$FORGEJO_RUNNER_STORAGE_MARKER" /etc/fstab; then
    fstab_tmp=$(mktemp /etc/fstab.forgejo-runner.XXXXXX)
    cp --preserve=mode,ownership /etc/fstab "$fstab_tmp"
    printf '\n%s\n%s %s xfs loop,noatime,nodev,nosuid,x-systemd.automount 0 0\n' \
      "$FORGEJO_RUNNER_STORAGE_MARKER" "$FORGEJO_RUNNER_STORAGE_IMAGE" "$storage_path" >>"$fstab_tmp"
    mv -fT "$fstab_tmp" /etc/fstab
  fi
  expected_line="$FORGEJO_RUNNER_STORAGE_IMAGE $storage_path xfs loop,noatime,nodev,nosuid,x-systemd.automount 0 0"
  grep -Fxq "$expected_line" /etc/fstab || die "Forgejo Runner storage fstab entry differs from policy"

  systemctl daemon-reload
  findmnt -n --mountpoint "$storage_path" >/dev/null 2>&1 || mount "$storage_path"
  loop_device=$(losetup -j "$FORGEJO_RUNNER_STORAGE_IMAGE" | cut -d: -f1 | head -1)
  mounted_source=$(findmnt -n -o SOURCE --mountpoint "$storage_path")
  [[ -n $loop_device && $mounted_source == "$loop_device" ]] || \
    die "Forgejo Runner storage is not mounted from its bounded image"
  chown "$runner_user:$runner_user" "$storage_path"
  chmod 0700 "$storage_path"
  restorecon -RF "$runner_home/.local" >/dev/null 2>&1 || true
}

forgejo_runner_configure_user_slice() {
  local runner_uid=$1 dropin_dir
  dropin_dir="/etc/systemd/system/user-${runner_uid}.slice.d"
  install -d -m 0755 "$dropin_dir"
  install -m 0644 /dev/stdin "$dropin_dir/forgejo-runner-limits.conf" <<EOF
[Slice]
MemoryMax=$FORGEJO_RUNNER_MEMORY_MAX
CPUQuota=$FORGEJO_RUNNER_CPU_QUOTA
TasksMax=$FORGEJO_RUNNER_TASKS_MAX
EOF
  systemctl daemon-reload
  if systemctl is-active --quiet "user-${runner_uid}.slice"; then
    systemctl set-property --runtime "user-${runner_uid}.slice" \
      "MemoryMax=$FORGEJO_RUNNER_MEMORY_MAX" \
      "CPUQuota=$FORGEJO_RUNNER_CPU_QUOTA" \
      "TasksMax=$FORGEJO_RUNNER_TASKS_MAX"
  fi
}

forgejo_runner_nft_elements() {
  local family=$1
  shift
  if (($# == 0)); then
    case "$family" in
      ipv4) printf '%s' '0.0.0.0' ;;
      ipv6) printf '%s' '::' ;;
    esac
    return
  fi
  case "$family" in
    ipv4) printf '%s\n' "$@" | awk '/^[0-9]+(\.[0-9]+){3}$/ && !seen[$0]++' | paste -sd, - ;;
    ipv6) printf '%s\n' "$@" | awk '/:/ && !seen[$0]++' | paste -sd, - ;;
    *) die "unsupported nftables address family: $family" ;;
  esac
}

forgejo_runner_render_egress() {
  local template=$1 output=$2 forgejo_host=$3
  local -a dns4=() dns6=() forgejo4=() forgejo6=()
  local address
  while read -r _ address _; do
    [[ -n $address ]] || continue
    case "$address" in
      *:*) dns6+=("$address") ;;
      *) dns4+=("$address") ;;
    esac
  done < <(awk '$1 == "nameserver" { print $1, $2, $3 }' /etc/resolv.conf)
  while read -r address _; do
    [[ -n $address ]] && forgejo4+=("$address")
  done < <(getent ahostsv4 "$forgejo_host" 2>/dev/null | awk '$2 == "STREAM" { print $1 }')
  while read -r address _; do
    [[ -n $address ]] && forgejo6+=("$address")
  done < <(getent ahostsv6 "$forgejo_host" 2>/dev/null | awk '$2 == "STREAM" { print $1 }')
  if [[ -n ${FORGEJO_RUNNER_EXTRA_FORGEJO_IPV4:-} ]]; then
    read -r -a extra_forgejo4 <<<"$FORGEJO_RUNNER_EXTRA_FORGEJO_IPV4"
    forgejo4+=("${extra_forgejo4[@]}")
  fi
  if [[ -n ${FORGEJO_RUNNER_EXTRA_FORGEJO_IPV6:-} ]]; then
    read -r -a extra_forgejo6 <<<"$FORGEJO_RUNNER_EXTRA_FORGEJO_IPV6"
    forgejo6+=("${extra_forgejo6[@]}")
  fi
  ((${#dns4[@]} + ${#dns6[@]} > 0)) || die "no DNS resolvers found for Forgejo Runner egress policy"
  ((${#forgejo4[@]} + ${#forgejo6[@]} > 0)) || die "cannot resolve $forgejo_host for Forgejo Runner egress policy"

  DNS_IPV4_ELEMENTS=$(forgejo_runner_nft_elements ipv4 "${dns4[@]}")
  DNS_IPV6_ELEMENTS=$(forgejo_runner_nft_elements ipv6 "${dns6[@]}")
  FORGEJO_IPV4_ELEMENTS=$(forgejo_runner_nft_elements ipv4 "${forgejo4[@]}")
  FORGEJO_IPV6_ELEMENTS=$(forgejo_runner_nft_elements ipv6 "${forgejo6[@]}")
  FORGEJO_RUNNER_ALLOWED_TCP_PORT=${FORGEJO_RUNNER_ALLOWED_TCP_PORT:-443}
  export DNS_IPV4_ELEMENTS DNS_IPV6_ELEMENTS FORGEJO_IPV4_ELEMENTS FORGEJO_IPV6_ELEMENTS
  export FORGEJO_RUNNER_ALLOWED_TCP_PORT
  # shellcheck disable=SC2016
  envsubst '${DNS_IPV4_ELEMENTS} ${DNS_IPV6_ELEMENTS} ${FORGEJO_IPV4_ELEMENTS} ${FORGEJO_IPV6_ELEMENTS} ${FORGEJO_RUNNER_ALLOWED_TCP_PORT}' \
    <"$template" >"$output"
  chmod 0644 "$output"
}

forgejo_runner_verify_storage() {
  local runner_home=$1 storage_path image_size loop_device mounted_source mounted_fstype expected_line
  storage_path=$(forgejo_runner_storage_path "$runner_home")
  [[ -f $FORGEJO_RUNNER_STORAGE_IMAGE ]] || die "Forgejo Runner bounded storage image is missing"
  image_size=$(stat -c %s "$FORGEJO_RUNNER_STORAGE_IMAGE")
  [[ $image_size == "$FORGEJO_RUNNER_STORAGE_BYTES" ]] || die "Forgejo Runner storage capacity is not bounded at $FORGEJO_RUNNER_STORAGE_SIZE"
  expected_line="$FORGEJO_RUNNER_STORAGE_IMAGE $storage_path xfs loop,noatime,nodev,nosuid,x-systemd.automount 0 0"
  grep -Fxq "$expected_line" /etc/fstab || die "Forgejo Runner bounded storage fstab entry differs from policy"
  if [[ $EUID -eq 0 ]]; then
    mounted_source=$(findmnt -n -o SOURCE --mountpoint "$storage_path" 2>/dev/null || true)
    mounted_fstype=$(findmnt -n -o FSTYPE --mountpoint "$storage_path" 2>/dev/null || true)
    [[ $mounted_source =~ ^/dev/loop[0-9]+$ && $mounted_fstype == xfs ]] || \
      die "Forgejo Runner bounded storage is not mounted"
    loop_device=$(losetup -j "$FORGEJO_RUNNER_STORAGE_IMAGE" | cut -d: -f1)
    grep -Fxq "$mounted_source" <<<"$loop_device" || \
      die "Forgejo Runner bounded storage is not backed by the configured image"
  fi
}
