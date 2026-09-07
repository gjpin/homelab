#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"

require_command jq
"$root/tests/architecture.sh"

load_host_tools "$root/config/host-tools.env"
for field in \
  AGE_RELEASE_TAG AGE_AMD64_TAR_SHA256 AGE_ARM64_TAR_SHA256 \
  RESTIC_RELEASE_TAG RESTIC_AMD64_BZ2_SHA256 RESTIC_ARM64_BZ2_SHA256 \
  SOPS_RELEASE_TAG SOPS_AMD64_BINARY_SHA256 SOPS_ARM64_BINARY_SHA256 \
  FORGEJO_RUNNER_RELEASE_TAG FORGEJO_RUNNER_AMD64_BINARY_SHA256 \
  FORGEJO_RUNNER_ARM64_BINARY_SHA256; do
  rg -q "^${field}=" "$root/config/host-tools.env" || die "host tools metadata is missing: $field"
done

rg -q 'age-keygen -pq -o' "$root/bin/bootstrap-host" || die "host age identity is not post-quantum"
rg -q '== debian' "$root/bin/bootstrap-host" || die "bootstrap does not require Debian"
if rg -n 'VERSION_ID' "$root/bin/bootstrap-host" | rg -v 'VERSION_CODENAME'; then
  die "bootstrap must not pin a Debian version ID"
fi

for helper in install-age install-restic install-sops install-forgejo-runner; do
  rg -q "install -m 0755 \"\\\$root/bin/$helper\" /usr/local/lib/homelab/$helper" \
    "$root/bin/bootstrap-host" || die "bootstrap does not install fixed helper $helper"
done
if rg -n 'ExecStart=.*(/home/homelab/current/bin|/current/bin)' \
  "$root/systemd/system/homelab-host-tools-update.service"; then
  die "host-tools service executes mutable Git content as root"
fi

[[ ! -e $root/quadlet ]] || die "quadlet/ must not exist on the docker branch"
[[ ! -e $root/selinux ]] || die "selinux/ must not exist on the docker branch"
[[ ! -e $root/incubator ]] || die "incubator/ must not exist on the docker branch"

while IFS= read -r app; do
  file="$root/compose/$app/compose.yaml"
  [[ -f $file ]] || die "missing compose file: $file"
  for key in 'restart: always' 'read_only: true' 'no-new-privileges:true' 'cap_drop:' 'pids_limit: 1024'; do
    rg -q -- "$key" "$file" || die "$file is missing hardening key: $key"
  done
  if rg -q 'apparmor=unconfined' "$file"; then
    die "$file disables AppArmor"
  fi
done < <(jq -r 'keys[]' "$root/manifests/applications.json")

rg -q 'image: ghcr.io/kozea/radicale:[^[:space:]]+@sha256:' "$root/compose/radicale/compose.yaml" || \
  die "radicale compose must pin the official Kozea image by digest"
rg -q 'user: "1000:1000"' "$root/compose/radicale/compose.yaml" || \
  die "radicale compose is missing non-root user"
[[ ! -e $root/images/radicale ]] || die "radicale must use the upstream image, not a custom build"

rg -q '443:443' "$root/compose/caddy/compose.yaml" || die "Caddy does not publish 443"
rg -q 'NET_BIND_SERVICE' "$root/compose/caddy/compose.yaml" || die "Caddy is missing NET_BIND_SERVICE"
rg -q '22000:22000/tcp' "$root/compose/syncthing/compose.yaml" || die "Syncthing is missing TCP 22000"
rg -q '22000:22000/udp' "$root/compose/syncthing/compose.yaml" || die "Syncthing is missing UDP 22000"

if rg -n 'ports:' "$root/compose" | rg -v 'caddy/compose.yaml|syncthing/compose.yaml'; then
  die "unexpected published ports outside Caddy and Syncthing"
fi

for backend in homelab-forgejo homelab-homeassistant homelab-immich homelab-searxng; do
  if rg -q "name: $backend$" "$root/compose/caddy/compose.yaml"; then
    die "Caddy compose references backend network $backend"
  fi
done

while IFS= read -r network; do
  jq -e --arg n "$network" '.[$n] | has("internal") and has("app")' \
    "$root/manifests/networks.json" >/dev/null || die "network inventory is incomplete: $network"
done < <(jq -r 'keys[]' "$root/manifests/networks.json")

if rg -n 'subnet:|ipam:' "$root/compose"; then
  die "compose must not assign subnets; let Docker allocate them"
fi

rg -q 'container_name: immich-redis' "$root/compose/immich/compose.yaml" || die "Immich must use Redis"
rg -q 'container_name: searxng-redis' "$root/compose/searxng/compose.yaml" || die "SearXNG must use Redis"
rg -q 'redis://searxng-redis:6379/0' "$root/config/templates/searxng/settings.yml" || \
  die "SearXNG settings do not point at Redis"
if rg -n 'valkey' "$root/compose" "$root/config/templates" "$root/manifests"; then
  die "Valkey references remain in the active deployment"
fi

rg -q '^[[:space:]]*apparmor$' "$root/bin/bootstrap-host" || die "bootstrap does not install AppArmor"
rg -q 'docker-ce' "$root/bin/bootstrap-host" || die "bootstrap does not install Docker CE"
rg -q 'usermod -aG docker' "$root/bin/bootstrap-host" || die "bootstrap does not add homelab to docker"

printf 'static checks passed\n'
