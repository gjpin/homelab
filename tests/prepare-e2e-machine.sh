#!/usr/bin/env bash
set -Eeuo pipefail

machine_user=$(id -un)
printf '%s:100000:1000000\n' "$machine_user" | \
  sudo tee /etc/subuid /etc/subgid >/dev/null
podman system migrate

uid_map_lines=$(podman unshare cat /proc/self/uid_map | wc -l)
gid_map_lines=$(podman unshare cat /proc/self/gid_map | wc -l)
if ((uid_map_lines < 2 || gid_map_lines < 2)); then
  printf 'rootless Podman did not acquire subordinate UID/GID mappings\n' >&2
  exit 1
fi
