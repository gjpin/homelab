#!/usr/bin/env bash
# Host-root helpers for mounting Podman graphroot on an external disk.
# Sourced by bin/bootstrap-host; not executed directly.

HOMELAB_STORAGE_FSTAB_MARKER="# homelab-podman-storage"
HOMELAB_STORAGE_FSTAB_OPTIONS="defaults,noatime,x-systemd.automount,x-systemd.device-timeout=30"
HOMELAB_STORAGE_PROMPT_DECLINED=10

homelab_storage_path() {
  printf '%s\n' "${HOMELAB_STORAGE_PATH:-/home/homelab/.local/share/containers/storage}"
}

homelab_storage_fstab() {
  printf '%s\n' "${HOMELAB_FSTAB:-/etc/fstab}"
}

homelab_storage_systemd_dir() {
  printf '%s\n' "${HOMELAB_SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
}

homelab_storage_by_id_dir() {
  printf '%s\n' "${HOMELAB_DISK_BY_ID_DIR:-/dev/disk/by-id}"
}

homelab_storage_canonical() {
  local path=$1
  if [[ -e $path ]]; then
    readlink -f -- "$path"
  else
    printf '%s\n' "$path"
  fi
}

homelab_storage_require_device() {
  local path=$1
  [[ -e $path ]] || die "data disk does not exist: $path"
  [[ ! -d $path ]] || die "data disk path is a directory: $path"
  if [[ ${HOMELAB_STORAGE_TEST:-0} != 1 ]]; then
    [[ -b $path ]] || die "data disk is not a block device: $path"
  fi
}

HOMELAB_STORAGE_INVENTORY_JSON=

homelab_storage_invalidate_inventory() {
  HOMELAB_STORAGE_INVENTORY_JSON=
}

homelab_storage_inventory() {
  require_command lsblk
  require_command jq
  local rec name pkname
  local -a items=()
  if [[ -n ${HOMELAB_STORAGE_INVENTORY_JSON:-} ]]; then
    printf '%s\n' "$HOMELAB_STORAGE_INVENTORY_JSON"
    return 0
  fi
  while IFS= read -r rec; do
    [[ -n $rec ]] || continue
    name=$(homelab_storage_canonical "$(jq -r '.name' <<<"$rec")")
    pkname=$(jq -r '.pkname' <<<"$rec")
    if [[ -n $pkname ]]; then
      pkname=$(homelab_storage_canonical "$pkname")
    fi
    items+=("$(jq -c --arg n "$name" --arg p "$pkname" '.name = $n | .pkname = $p' <<<"$rec")")
  done < <(
    lsblk -J -p -o NAME,SIZE,MODEL,TRAN,TYPE,FSTYPE,UUID,PKNAME,MOUNTPOINT | jq -c '
      def flatten:
        (
          del(.children)
          | .pkname = (
              if .pkname == null or .pkname == "" then ""
              elif (.pkname | startswith("/")) then .pkname
              else "/dev/\(.pkname)" end
            )
          | .fstype = (.fstype // "")
          | .uuid = (.uuid // "")
          | .model = (.model // "")
          | .tran = (.tran // "")
          | .mountpoint = (.mountpoint // "")
          | .size = ((.size // "") | tostring)
          | .type = (.type // "")
          | .name = (.name // "")
        ),
        ((.children // [])[] | flatten);
      .blockdevices[] | flatten
    '
  )
  if ((${#items[@]} == 0)); then
    HOMELAB_STORAGE_INVENTORY_JSON='[]'
    printf '[]\n'
    return 0
  fi
  HOMELAB_STORAGE_INVENTORY_JSON=$(printf '%s\n' "${items[@]}" | jq -s -c '.')
  printf '%s\n' "$HOMELAB_STORAGE_INVENTORY_JSON"
}

homelab_storage_device_record() {
  local name=$1
  local inv
  inv=$(homelab_storage_inventory)
  jq -c --arg n "$name" '.[] | select(.name == $n)' <<<"$inv"
}

homelab_storage_device_field() {
  local name=$1 field=$2
  local record
  record=$(homelab_storage_device_record "$name")
  [[ -n $record ]] || die "block device is not in the host inventory: $name"
  jq -r --arg field "$field" '.[$field] // empty' <<<"$record"
}

homelab_storage_parent() {
  local name=$1
  local inv
  inv=$(homelab_storage_inventory)
  jq -r --arg n "$name" '.[] | select(.name == $n) | .pkname' <<<"$inv"
}

homelab_storage_by_id() {
  local target=$1 id preferred='' fallback=''
  local dir
  target=$(homelab_storage_canonical "$target")
  dir=$(homelab_storage_by_id_dir)
  [[ -d $dir ]] || {
    printf '%s\n' "$target"
    return
  }
  shopt -s nullglob
  for id in "$dir"/*; do
    [[ $(homelab_storage_canonical "$id") == "$target" ]] || continue
    case "$(basename -- "$id")" in
      wwn-*|nvme-eui.*|nvme-nvme.*)
        [[ -n $fallback ]] || fallback=$id
        ;;
      *)
        preferred=$id
        break
        ;;
    esac
  done
  shopt -u nullglob
  printf '%s\n' "${preferred:-${fallback:-$target}}"
}

homelab_storage_os_sources() {
  local target source
  require_command findmnt
  for target in / /home; do
    source=$(findmnt -n --nofsroot -o SOURCE --target "$target" 2>/dev/null || true)
    [[ -n $source ]] || continue
    homelab_storage_canonical "$source"
  done
}

homelab_storage_is_os_device() {
  local name=$1
  local source parent inv
  name=$(homelab_storage_canonical "$name")
  inv=$(homelab_storage_inventory)
  while IFS= read -r source; do
    [[ -n $source ]] || continue
    source=$(homelab_storage_canonical "$source")
    [[ $name == "$source" ]] && return 0
    parent=$name
    while [[ -n $parent ]]; do
      [[ $parent == "$source" ]] && return 0
      parent=$(jq -r --arg n "$parent" '.[] | select(.name == $n) | .pkname' <<<"$inv")
      [[ -n $parent ]] && parent=$(homelab_storage_canonical "$parent")
    done
    parent=$source
    while [[ -n $parent ]]; do
      [[ $parent == "$name" ]] && return 0
      parent=$(jq -r --arg n "$parent" '.[] | select(.name == $n) | .pkname' <<<"$inv")
      [[ -n $parent ]] && parent=$(homelab_storage_canonical "$parent")
    done
  done < <(homelab_storage_os_sources)
  return 1
}

homelab_storage_is_virtual_type() {
  case "$1" in
    loop|rom|ram|zram) return 0 ;;
    *) return 1 ;;
  esac
}

homelab_storage_is_mounted_under() {
  local root=$1
  local inv name parent
  inv=$(homelab_storage_inventory)
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    parent=$name
    while [[ -n $parent ]]; do
      [[ $parent == "$root" ]] && return 0
      parent=$(jq -r --arg n "$parent" '.[] | select(.name == $n) | .pkname' <<<"$inv")
    done
  done < <(jq -r '.[] | select(.mountpoint != "") | .name' <<<"$inv")
  return 1
}

homelab_storage_assert_not_os_device() {
  local name=$1
  if homelab_storage_is_os_device "$name"; then
    die "refusing to use the operating system disk for Podman storage: $name"
  fi
}

homelab_storage_candidate_lines() {
  local inv name type fstype size model tran display
  inv=$(homelab_storage_inventory)
  while IFS=$'\t' read -r name type fstype size model tran; do
    [[ -n $name ]] || continue
    [[ $fstype == - ]] && fstype=
    [[ $model == - ]] && model=
    [[ $tran == - ]] && tran=
    homelab_storage_is_virtual_type "$type" && continue
    homelab_storage_is_os_device "$name" && continue
    display=$(homelab_storage_by_id "$name")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$name" "$display" "$type" "$fstype" "$size" "$model" "$tran"
  done < <(jq -r '
    .[]
    | select(.type == "disk" or .type == "part")
    | select(.mountpoint == "")
    | [.name, .type, (.fstype // "-"), .size, (.model // "-"), (.tran // "-")]
    | @tsv
  ' <<<"$inv")
}

homelab_storage_fstype() {
  local device=$1 value record
  require_command blkid
  value=$(blkid -s TYPE -o value "$device" 2>/dev/null || true)
  if [[ -z $value ]]; then
    record=$(homelab_storage_inventory | jq -r --arg n "$device" '.[] | select(.name == $n) | .fstype')
    value=$record
  fi
  printf '%s\n' "$value"
}

homelab_storage_uuid() {
  local device=$1 value record
  require_command blkid
  value=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
  if [[ -z $value ]]; then
    record=$(homelab_storage_inventory | jq -r --arg n "$device" '.[] | select(.name == $n) | .uuid')
    value=$record
  fi
  printf '%s\n' "$value"
}

homelab_storage_require_uuid() {
  local uuid=$1
  [[ $uuid =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || \
    die "block device UUID is invalid: ${uuid:-<empty>}"
}

homelab_storage_require_fstype() {
  local fstype=$1
  case "$fstype" in
    xfs|ext4) ;;
    *) die "existing data disk must be xfs or ext4 (got ${fstype:-<empty>}); choose format for a new disk" ;;
  esac
}

homelab_storage_dir_has_entries() {
  local path=$1
  local entries
  local prev_nullglob prev_dotglob
  prev_nullglob=$(shopt -p nullglob)
  prev_dotglob=$(shopt -p dotglob)
  shopt -s nullglob dotglob
  entries=("$path"/*)
  eval "$prev_nullglob"
  eval "$prev_dotglob"
  ((${#entries[@]} > 0))
}

homelab_storage_path_is_mounted() {
  local path=$1
  require_command findmnt
  findmnt -n --target "$path" >/dev/null 2>&1
}

homelab_storage_managed_fstab_line() {
  local fstab marker
  fstab=$(homelab_storage_fstab)
  marker=$HOMELAB_STORAGE_FSTAB_MARKER
  [[ -f $fstab ]] || return 0
  awk -v marker="$marker" '
    $0 == marker {
      if ((getline nxt) <= 0) {
        exit 2
      }
      print nxt
      exit 0
    }
  ' "$fstab"
}

homelab_storage_fstab_is_managed() {
  local line
  line=$(homelab_storage_managed_fstab_line || true)
  [[ $line == UUID=* ]]
}

homelab_storage_managed_uuid() {
  local line
  line=$(homelab_storage_managed_fstab_line)
  [[ $line == UUID=* ]] || die "managed Podman storage fstab stanza is missing"
  line=${line#UUID=}
  printf '%s\n' "${line%%[[:space:]]*}"
}

homelab_storage_already_mounted_correctly() {
  local path uuid mounted
  path=$(homelab_storage_path)
  homelab_storage_fstab_is_managed || return 1
  homelab_storage_path_is_mounted "$path" || return 1
  uuid=$(homelab_storage_managed_uuid)
  mounted=$(findmnt -n -o UUID --target "$path" 2>/dev/null || true)
  [[ $mounted == "$uuid" ]]
}

homelab_storage_fstab_without_managed() {
  local fstab marker path
  fstab=$(homelab_storage_fstab)
  marker=$HOMELAB_STORAGE_FSTAB_MARKER
  path=$(homelab_storage_path)
  if [[ ! -f $fstab ]]; then
    return 0
  fi
  awk -v marker="$marker" -v path="$path" '
    $0 == marker {
      if ((getline nxt) <= 0) {
        printf "error: managed fstab marker is missing its mount line\n" > "/dev/stderr"
        exit 2
      }
      if (nxt !~ /^UUID=[^[:space:]]+[[:space:]]/) {
        printf "error: managed fstab stanza is malformed\n" > "/dev/stderr"
        exit 2
      }
      next
    }
    $1 !~ /^#/ && $2 == path {
      printf "error: refusing to replace unmanaged fstab entry for %s\n", path > "/dev/stderr"
      exit 3
    }
    { print }
  ' "$fstab" || die "cannot rewrite the Podman storage fstab stanza"
}

homelab_storage_write_fstab() {
  local uuid=$1 fstype=$2
  local fstab path tmp
  homelab_storage_require_uuid "$uuid"
  homelab_storage_require_fstype "$fstype"
  fstab=$(homelab_storage_fstab)
  path=$(homelab_storage_path)
  tmp=$(mktemp)
  homelab_storage_fstab_without_managed >"$tmp"
  printf '%s\n' "$HOMELAB_STORAGE_FSTAB_MARKER" >>"$tmp"
  printf 'UUID=%s %s %s %s 0 2\n' \
    "$uuid" "$path" "$fstype" "$HOMELAB_STORAGE_FSTAB_OPTIONS" >>"$tmp"
  install -m 0644 "$tmp" "$fstab"
  rm -f -- "$tmp"
}

homelab_storage_systemd_path_unit() {
  local path=$1 suffix=$2
  local result='' part escaped
  if command -v systemd-escape >/dev/null 2>&1; then
    systemd-escape --path --suffix="$suffix" "$path"
    return
  fi
  path=${path#/}
  path=${path%/}
  while [[ -n $path ]]; do
    part=${path%%/*}
    if [[ $path == */* ]]; then
      path=${path#*/}
    else
      path=
    fi
    escaped=${part//-/\\x2d}
    if [[ -n $result ]]; then
      result+="-$escaped"
    else
      result=$escaped
    fi
  done
  printf '%s.%s\n' "$result" "$suffix"
}

homelab_storage_write_user_dropin() {
  local user=$1
  local uid dir path
  uid=$(id -u "$user")
  path=$(homelab_storage_path)
  dir="$(homelab_storage_systemd_dir)/user@${uid}.service.d"
  install -d -m 0755 "$dir"
  cat >"$dir/homelab-storage.conf" <<EOF
[Unit]
RequiresMountsFor=$path
EOF
  chmod 0644 "$dir/homelab-storage.conf"
}

homelab_storage_prepare_mountpoint() {
  local path home user
  path=$(homelab_storage_path)
  user=${1:-homelab}
  home=${HOMELAB_RUNTIME_HOME:-/home/homelab}
  install -d -m 0700 -o "$(id -u "$user")" -g "$(id -g "$user")" \
    "$home/.local" "$home/.local/share" "$home/.local/share/containers" "$path"
  if homelab_storage_path_is_mounted "$path"; then
    return 0
  fi
  if homelab_storage_dir_has_entries "$path"; then
    die "refusing to mount over a non-empty directory: $path"
  fi
}

homelab_storage_activate_mount() {
  local path mount_unit automount_unit
  path=$(homelab_storage_path)
  require_command systemctl
  require_command findmnt
  mount_unit=$(homelab_storage_systemd_path_unit "$path" mount)
  automount_unit=$(homelab_storage_systemd_path_unit "$path" automount)
  systemctl daemon-reload
  # The fstab generator wires this unit into local-fs.target for future boots.
  # Generated units cannot be enabled with systemctl, so only start it now.
  systemctl start "$automount_unit"
  systemctl start "$mount_unit"
  homelab_storage_path_is_mounted "$path" || \
    die "failed to mount Podman storage at $path"
}

homelab_storage_label_mount() {
  local path user uid gid
  path=$(homelab_storage_path)
  user=$1
  uid=$(id -u "$user")
  gid=$(id -g "$user")
  chown "$uid:$gid" "$path"
  require_command restorecon
  restorecon -Rv "$path" >/dev/null
}

homelab_storage_wait_for_partition() {
  local disk=$1
  local inv child
  require_command udevadm
  for _ in $(seq 1 20); do
    udevadm settle || true
    homelab_storage_invalidate_inventory
    inv=$(homelab_storage_inventory)
    child=$(jq -r --arg disk "$disk" '
      .[] | select(.pkname == $disk and .type == "part") | .name
    ' <<<"$inv" | sed -n '1p')
    if [[ -n $child ]]; then
      printf '%s\n' "$child"
      return 0
    fi
    sleep 0.25
  done
  die "formatted disk did not produce a partition: $disk"
}

homelab_storage_format_device() {
  local device=$1
  local type filesystem
  require_command wipefs
  require_command mkfs.xfs
  type=$(homelab_storage_device_field "$device" type)
  homelab_storage_assert_not_os_device "$device"
  case "$type" in
    disk)
      if homelab_storage_is_mounted_under "$device"; then
        die "refusing to format a disk that has mounted filesystems: $device"
      fi
      require_command sfdisk
      info "creating a GPT partition table on $device"
      wipefs -a "$device" >/dev/null
      sfdisk --wipe always --wipe-partitions always "$device" >/dev/null <<'EOF'
label: gpt
,+,0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
      homelab_storage_invalidate_inventory
      filesystem=$(homelab_storage_wait_for_partition "$device")
      ;;
    part)
      if homelab_storage_is_mounted_under "$device"; then
        die "refusing to format a mounted partition: $device"
      fi
      info "creating XFS on $device"
      wipefs -a "$device" >/dev/null
      filesystem=$device
      ;;
    *)
      die "can only format a disk or partition: $device ($type)"
      ;;
  esac
  homelab_storage_require_device "$filesystem"
  mkfs.xfs -f -L homelab-storage "$filesystem" >/dev/null
  printf '%s\n' "$filesystem"
}

homelab_storage_existing_children() {
  local disk=$1
  local inv
  inv=$(homelab_storage_inventory)
  jq -r --arg disk "$disk" '
    .[] | select(.pkname == $disk and .type == "part" and .mountpoint == "" and (.fstype == "xfs" or .fstype == "ext4")) | .name
  ' <<<"$inv"
}

homelab_storage_resolve_existing() {
  local device=$1
  local allow_prompt=${2:-false}
  local type fstype children child count display
  homelab_storage_require_device "$device"
  device=$(homelab_storage_canonical "$device")
  type=$(homelab_storage_device_field "$device" type)
  homelab_storage_assert_not_os_device "$device"
  if homelab_storage_is_virtual_type "$type"; then
    die "refusing to use a virtual block device: $device"
  fi
  case "$type" in
    part)
      if homelab_storage_is_mounted_under "$device"; then
        die "data disk is already mounted: $device"
      fi
      fstype=$(homelab_storage_fstype "$device")
      homelab_storage_require_fstype "$fstype"
      printf '%s\n' "$device"
      ;;
    disk)
      fstype=$(homelab_storage_fstype "$device")
      if [[ $fstype == xfs || $fstype == ext4 ]]; then
        if homelab_storage_is_mounted_under "$device"; then
          die "data disk is already mounted: $device"
        fi
        printf '%s\n' "$device"
        return 0
      fi
      mapfile -t children < <(homelab_storage_existing_children "$device")
      count=${#children[@]}
      if ((count == 1)); then
        printf '%s\n' "${children[0]}"
        return 0
      fi
      if ((count == 0)); then
        die "no xfs or ext4 filesystem found on $device; choose format for a new disk"
      fi
      if [[ $allow_prompt != true ]]; then
        die "disk $device has multiple filesystems; pass a partition path to --data-disk"
      fi
      printf 'Multiple filesystems on %s:\n' "$device" >&2
      local i=1
      for child in "${children[@]}"; do
        display=$(homelab_storage_by_id "$child")
        printf '  %s) %s (%s)\n' "$i" "$display" "$(homelab_storage_fstype "$child")" >&2
        i=$((i + 1))
      done
      local answer
      answer=$(homelab_storage_read_tty 'Select a partition by number: ')
      [[ $answer =~ ^[1-9][0-9]*$ ]] || die "invalid partition selection"
      ((answer >= 1 && answer <= count)) || die "invalid partition selection"
      printf '%s\n' "${children[answer-1]}"
      ;;
    *)
      die "data disk must be a whole disk or partition: $device"
      ;;
  esac
}

homelab_storage_assert_device_matches_configured() {
  local device=$1
  local configured filesystem uuid
  homelab_storage_require_device "$device"
  device=$(homelab_storage_canonical "$device")
  filesystem=$(homelab_storage_resolve_existing "$device" false)
  uuid=$(homelab_storage_uuid "$filesystem")
  configured=$(homelab_storage_managed_uuid)
  [[ $uuid == "$configured" ]] || \
    die "selected data disk UUID $uuid does not match the configured storage disk $configured"
}

homelab_storage_apply() {
  local device=$1
  local format=$2
  local user=$3
  local filesystem uuid fstype
  [[ $format == true || $format == false ]] || die "format flag must be true or false"
  [[ -n $user ]] || die "runtime user is required"
  homelab_storage_require_device "$device"
  device=$(homelab_storage_canonical "$device")
  homelab_storage_assert_not_os_device "$device"
  if [[ $format == true ]]; then
    filesystem=$(homelab_storage_format_device "$device")
  else
    filesystem=$(homelab_storage_resolve_existing "$device" false)
  fi
  uuid=$(homelab_storage_uuid "$filesystem")
  fstype=$(homelab_storage_fstype "$filesystem")
  homelab_storage_require_uuid "$uuid"
  homelab_storage_require_fstype "$fstype"
  homelab_storage_prepare_mountpoint "$user"
  homelab_storage_write_fstab "$uuid" "$fstype"
  homelab_storage_write_user_dropin "$user"
  homelab_storage_activate_mount
  homelab_storage_label_mount "$user"
  info "Podman storage is mounted at $(homelab_storage_path)"
}

homelab_storage_read_tty() {
  local prompt=$1 value
  if [[ -n ${HOMELAB_STORAGE_TTY_FD:-} ]]; then
    printf '%s' "$prompt" >&2
    read -r value <&"$HOMELAB_STORAGE_TTY_FD"
  else
    read -r -p "$prompt" value </dev/tty
  fi
  printf '%s' "$value"
}

homelab_storage_prompt() {
  local path answer i line name display type fstype size model tran
  local -a names
  local -a lines
  local selected format_choice by_id confirm_line confirm_word confirm_dev
  path=$(homelab_storage_path)
  printf '\nThis host can keep Podman images and named volumes on an external disk\nmounted at %s.\nTreat that disk as permanently attached; do not unplug it while services run.\n\n' "$path" >&2
  answer=$(homelab_storage_read_tty 'Use an external data disk? [y/N] ')
  [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]] || return "$HOMELAB_STORAGE_PROMPT_DECLINED"
  mapfile -t lines < <(homelab_storage_candidate_lines)
  ((${#lines[@]} > 0)) || die "no unused disks or partitions were found"
  printf 'Available devices:\n' >&2
  for i in "${!lines[@]}"; do
    IFS=$'\t' read -r name display type fstype size model tran <<<"${lines[$i]}"
    names+=("$name")
    printf '  %s) %s  %s  %s  %s' "$((i + 1))" "$display" "$size" "$type" "$tran" >&2
    [[ -n $model ]] && printf '  %s' "$model" >&2
    [[ -n $fstype ]] && printf '  %s' "$fstype" >&2
    printf '\n' >&2
  done
  answer=$(homelab_storage_read_tty 'Select a device by number: ')
  [[ $answer =~ ^[1-9][0-9]*$ ]] || die "invalid device selection"
  ((answer >= 1 && answer <= ${#names[@]})) || die "invalid device selection"
  selected=${names[answer-1]}
  printf '  1) Format (XFS, destroys all data)\n  2) Use existing filesystem\n' >&2
  format_choice=$(homelab_storage_read_tty 'Format this device or use an existing filesystem? [1/2] ')
  case "$format_choice" in
    1)
      by_id=$(homelab_storage_by_id "$selected")
      printf 'This will erase %s.\n' "$by_id" >&2
      confirm_line=$(homelab_storage_read_tty "Type FORMAT and $by_id to continue: ")
      read -r confirm_word confirm_dev <<<"$confirm_line"
      [[ $confirm_word == FORMAT && $confirm_dev == "$by_id" ]] || \
        die "format confirmation did not match"
      printf '%s\ttrue\n' "$selected"
      ;;
    2)
      selected=$(homelab_storage_resolve_existing "$selected" true)
      printf '%s\tfalse\n' "$selected"
      ;;
    *)
      die "invalid format selection"
      ;;
  esac
}

homelab_storage_setup() {
  local mode=$1
  local device=$2
  local format=$3
  local user=$4
  local selection
  [[ $mode == auto || $mode == skip || $mode == use ]] || \
    die "invalid data disk mode: $mode"
  [[ $format == true || $format == false ]] || die "format flag must be true or false"
  [[ -n $user ]] || die "runtime user is required"

  if homelab_storage_fstab_is_managed; then
    [[ $format == false ]] || die "refusing to format the configured Podman storage disk"
    if [[ $mode == use ]]; then
      homelab_storage_assert_device_matches_configured "$device"
    fi
    homelab_storage_write_user_dropin "$user"
    if homelab_storage_already_mounted_correctly; then
      info "Podman storage disk already mounted at $(homelab_storage_path)"
      return 0
    fi
    info "Mounting the configured Podman storage disk"
    homelab_storage_prepare_mountpoint "$user"
    homelab_storage_activate_mount
    homelab_storage_label_mount "$user"
    return 0
  fi

  if [[ $mode == skip ]]; then
    return 0
  fi
  if [[ $mode == auto ]]; then
    if [[ -z ${HOMELAB_STORAGE_TTY_FD:-} && ( ! -t 0 || ! -e /dev/tty ) ]]; then
      return 0
    fi
    if selection=$(homelab_storage_prompt); then
      :
    else
      local prompt_status=$?
      ((prompt_status == HOMELAB_STORAGE_PROMPT_DECLINED)) && return 0
      return "$prompt_status"
    fi
    device=${selection%%$'\t'*}
    format=${selection#*$'\t'}
  fi
  [[ -n $device ]] || die "--data-disk is required"
  [[ $device == /dev/* ]] || die "--data-disk must be an absolute /dev path"
  homelab_storage_apply "$device" "$format" "$user"
}
