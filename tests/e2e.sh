#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# This test intentionally uses the real Podman Quadlet generator and systemd
# user manager. It is invoked by bin/e2e inside a disposable Fedora machine.
source_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$source_root/bin/lib.sh"
export PATH="$HOME/.local/bin:$PATH"

usage() {
  cat <<'EOF'
Usage: tests/e2e.sh [--workload NAME ... | --container NAME]

Run the real rootless Podman E2E suite. With no selector, every workload and
container is started and checked. A workload selector checks all containers in
that application and may be repeated. A container selector checks that
container and its declared container dependencies.
EOF
}

selector_mode=all
selector=
selected_workloads=()
while (($#)); do
  case "$1" in
    --workload)
      [[ $selector_mode == all || $selector_mode == workload ]] || \
        die "--workload and --container cannot be combined"
      [[ $# -ge 2 ]] || die "$1 requires a name"
      [[ $2 =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid selector: $2"
      selector_mode=workload
      selected_workloads+=("$2")
      shift 2
      ;;
    --container)
      [[ $selector_mode == all ]] || die "--workload and --container cannot be combined"
      [[ $# -ge 2 ]] || die "$1 requires a name"
      [[ $2 =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid selector: $2"
      selector_mode=container
      selector=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_command age-keygen
require_command getenforce
require_command jq
require_command podman
require_command sops
require_command systemctl

[[ $EUID -ne 0 ]] || die "E2E must run rootless, not as root"
[[ $(getenforce) == Enforcing ]] || die "SELinux must be enforcing"
[[ -r /sys/fs/cgroup/cgroup.controllers ]] || die "cgroup v2 is required"
systemctl --user is-system-running 2>/dev/null | grep -Fxq running || {
  die "the systemd user manager is not running"
}

manifest="$source_root/manifests/applications.json"
readiness="$source_root/tests/e2e-readiness.json"
jq -e 'type == "object" and length > 0' "$manifest" >/dev/null
jq -e '.version == 1 and (.containers | type == "object")' "$readiness" >/dev/null

test_parent=$(mktemp -d "$HOME/homelab-e2e.XXXXXX")
test_root="$test_parent/repository"
unit_dir="$HOME/.config/systemd/user"
quadlet_dir="$HOME/.config/containers/systemd"
systemd_links=()
expected_units=()
expected_names=()
start_units=()
sops_key_file=
cleanup_done=false

cleanup() {
  local status=$?
  [[ $cleanup_done == true ]] && return
  cleanup_done=true

  set +e
  if ((status != 0)); then
    printf '\nE2E failed; collecting runtime diagnostics\n' >&2
    podman ps -a --format 'table {{.Names}}\t{{.Status}}' >&2
    for unit in "${expected_units[@]}"; do
      systemctl --user status --no-pager "$unit" >&2
      journalctl --user -u "$unit" -n 80 --no-pager >&2
    done
    for name in "${expected_names[@]}"; do
      podman logs --tail 80 "$name" >&2
    done
  fi

  stop_units=(homelab.target)
  while IFS= read -r app; do
    stop_units+=("homelab-$app.target")
  done < <(jq -r 'keys[]' "$manifest" 2>/dev/null)
  systemctl --user stop "${stop_units[@]}" "${expected_units[@]}" >/dev/null 2>&1
  systemctl --user reset-failed >/dev/null 2>&1

  podman rm -f "${expected_names[@]}" >/dev/null 2>&1
  while IFS= read -r network; do
    podman network rm -f "$network" >/dev/null 2>&1
  done < <(sed -n 's/^NetworkName=//p' "$test_root"/quadlet/networks/*.network 2>/dev/null)
  while IFS= read -r volume; do
    podman volume rm -f "$volume" >/dev/null 2>&1
  done < <(sed -n 's/^VolumeName=//p' "$test_root"/quadlet/volumes/*.volume 2>/dev/null)
  for secret in \
    caddy-cloudflare-api-token \
    caddy-bookmarks-password-hash \
    forgejo-database-password \
    homeassistant-mosquitto-password \
    immich-database-password \
    radicale-htpasswd-record \
    searxng-secret-key \
    supernote-database-root-password \
    supernote-database-user-password \
    supernote-valkey-password \
    vaultwarden-admin-token; do
    podman secret rm -f "$secret" >/dev/null 2>&1
  done
  for link in "${systemd_links[@]}"; do
    rm -f -- "$link"
  done
  [[ -z ${sops_key_file:-} ]] || rm -f -- "$sops_key_file"
  rm -f -- "$quadlet_dir/homelab" "$HOME/current"
  rm -rf -- "$test_parent"
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

if [[ -e $HOME/current || -L $HOME/current ]]; then
  die "$HOME/current already exists; refusing to touch an existing deployment"
fi
if [[ -e $quadlet_dir/homelab || -L $quadlet_dir/homelab ]]; then
  die "$quadlet_dir/homelab already exists; refusing to touch an existing deployment"
fi

install -d -m 0700 "$test_root"
cp -a "$source_root/." "$test_root/"
sed -i \
  "/^ExecStart=/i Environment=PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin" \
  "$test_root/systemd/user/homelab-secrets.service"
ln -s "$test_root" "$HOME/current"
install -d -m 0700 "$unit_dir" "$quadlet_dir"
ln -s "$test_root/quadlet" "$quadlet_dir/homelab"

while IFS= read -r source; do
  link="$unit_dir/$(basename -- "$source")"
  [[ -e $link || -L $link ]] && die "user unit already exists: $link"
  ln -s "$source" "$link"
  systemd_links+=("$link")
done < <(find "$test_root/systemd/user" -maxdepth 1 -type f \( -name '*.service' -o -name '*.target' -o -name '*.timer' \) | sort)

printf '%s\n' \
  'BASE_DOMAIN=e2e.test' \
  'TIMEZONE=Europe/Lisbon' \
  'HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID=e2e-fixture' \
  'BACKUP_S3_ENDPOINT=https://s3.e2e.test' \
  'BACKUP_S3_REGION=us-east-1' \
  'BACKUP_S3_BUCKET=homelab-e2e' \
  'BACKUP_S3_PREFIX=e2e' \
  >"$test_root/config/site.env"

cat >"$test_root/config/templates/caddy/Caddyfile" <<'EOF'
{
    auto_https off
}

:443 {
    tls internal
    respond "e2e ok" 200
}
EOF

cat >"$test_root/secrets/e2e-plaintext.yaml" <<'EOF'
backup:
  s3_access_key_id: e2e-access-key
  s3_secret_access_key: e2e-secret-key
  repository_password: e2e-repository-password-0123456789
caddy:
  cloudflare_api_token: e2e-cloudflare-token
  bookmarks_password_hash: e2e-bookmarks-hash
forgejo:
  database_password: e2e-forgejo-password
homeassistant:
  mosquitto_password: e2e-mosquitto-password
immich:
  database_password: e2e-immich-password
radicale:
  htpasswd_record: 'admin:$2y$05$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'
searxng:
  secret_key: e2e-searxng-secret-key
supernote:
  database_root_password: e2e-supernote-root-password
  database_user_password: e2e-supernote-user-password
  valkey_password: e2e-supernote-valkey-password
vaultwarden:
  admin_token_hash: e2e-vaultwarden-admin-token
EOF

key_dir="$test_parent/keys"
install -d -m 0700 "$key_dir"
age-keygen -pq -o "$key_dir/host.txt" >/dev/null
age-keygen -pq -o "$key_dir/operator.txt" >/dev/null
host_recipient=$(age-keygen -y "$key_dir/host.txt")
operator_recipient=$(age-keygen -y "$key_dir/operator.txt")
cat "$key_dir/host.txt" "$key_dir/operator.txt" >"$key_dir/keys.txt"
chmod 0600 "$key_dir/keys.txt"
sops_key_file="$HOME/.config/sops/age/keys.txt"
[[ -e $sops_key_file || -L $sops_key_file ]] && \
  die "$sops_key_file already exists; refusing to overwrite an existing key"
install -d -m 0700 "$(dirname -- "$sops_key_file")"
install -m 0600 "$key_dir/keys.txt" "$sops_key_file"
export SOPS_AGE_KEY_FILE="$key_dir/keys.txt"
sops --encrypt \
  --age "$host_recipient,$operator_recipient" \
  --input-type yaml \
  --output-type yaml \
  "$test_root/secrets/e2e-plaintext.yaml" \
  >"$test_root/secrets/secrets.sops.yaml"
rm -f -- "$test_root/secrets/e2e-plaintext.yaml"

mkdir -p "$test_root/assets/supernote"
[[ -e "$test_root/assets/supernote/supernotedb.sql" ]] && \
  chmod u+w -- "$test_root/assets/supernote/supernotedb.sql"
: >"$test_root/assets/supernote/supernotedb.sql"
sed -i \
  -e 's#^Image=.*#Image=localhost/homelab/e2e-zigbee2mqtt#' \
  -e '/^AddDevice=/d' \
  "$test_root/quadlet/applications/homeassistant/homeassistant-zigbee2mqtt.container"
sed -i '/^Secret=immich-database-password/a Environment=IGNORE_DATABASE_FSTYPE=true' \
  "$test_root/quadlet/applications/immich/immich-postgres.container"
sed -i \
  -e '/^PublishPort=22000:22000\/tcp$/d' \
  -e '/^PublishPort=22000:22000\/udp$/d' \
  "$test_root/quadlet/applications/syncthing/syncthing.container"
sed -i '/^RunInit=true$/d' \
  "$test_root/quadlet/applications/homeassistant/homeassistant-zigbee2mqtt.container"
podman build --pull=missing --tag localhost/homelab/e2e-zigbee2mqtt \
  "$test_root/tests/fixtures/zigbee2mqtt"

declare -A seen_units=()
add_required_units() {
  local unit=$1 file requirement
  [[ ${seen_units[$unit]:-false} == true ]] && return
  seen_units[$unit]=true
  expected_units+=("$unit")
  file=$(find "$test_root/quadlet/applications" -type f -name "${unit%.service}.container" -print -quit)
  [[ -n $file ]] || return
  while IFS= read -r requirement; do
    [[ $requirement == *.container ]] || continue
    add_required_units "${requirement%.container}.service"
  done < <(sed -n 's/^Requires=//p' "$file" | tr ' ' '\n')
}

case "$selector_mode" in
  all)
    start_units=(homelab.target)
    mapfile -t expected_units < <(
      jq -r '.[] .units[] | select(endswith(".service")) | select(endswith("-build.service") | not)' "$manifest"
    )
    ;;
  workload)
    for workload in "${selected_workloads[@]}"; do
      jq -e --arg workload "$workload" 'has($workload)' "$manifest" >/dev/null || \
        die "unknown workload: $workload"
      start_units+=("homelab-$workload.target")
      while IFS= read -r unit; do
        add_required_units "$unit"
      done < <(
        jq -r --arg workload "$workload" \
          '.[$workload].units[] | select(endswith(".service")) | select(endswith("-build.service") | not)' \
          "$manifest"
      )
    done
    ;;
  container)
    selected_file=$(find "$test_root/quadlet/applications" -type f -name '*.container' \
      -exec sh -c 'grep -q "^ContainerName=$1$" "$2"' _ "$selector" {} \; \
      -print -quit)
    [[ -n $selected_file ]] || die "unknown container: $selector"
    selected_unit="$(basename -- "$selected_file" .container).service"
    start_units=("$selected_unit")
    add_required_units "$selected_unit"
    ;;
esac

mapfile -t expected_units < <(printf '%s\n' "${expected_units[@]}" | sort -u)
mapfile -t start_units < <(printf '%s\n' "${start_units[@]}" | sed '/^$/d' | sort -u)
while IFS= read -r unit; do
  file=$(find "$test_root/quadlet/applications" -type f -name "${unit%.service}.container" -print -quit)
  [[ -n $file ]] || die "manifest unit has no Quadlet: $unit"
  name=$(sed -n 's/^ContainerName=//p' "$file")
  [[ -n $name ]] || die "missing ContainerName: $file"
  expected_names+=("$name")
done < <(printf '%s\n' "${expected_units[@]}")

systemctl --user daemon-reload
systemctl --user start --no-block "${start_units[@]}"

probe_image=docker.io/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
timeout_seconds=${E2E_TIMEOUT_SECONDS:-900}
deadline=$((SECONDS + timeout_seconds))

check_runtime() {
  local unit name inspection status mode network port
  for unit in "${expected_units[@]}"; do
    status=$(systemctl --user is-active "$unit" 2>/dev/null || true)
    if [[ $status != active ]]; then
      systemctl --user start --no-block "$unit" >/dev/null 2>&1 || true
      return 1
    fi
  done
  for name in "${expected_names[@]}"; do
    inspection=$(podman inspect "$name" 2>/dev/null) || return 1
    jq -e '.[0].State.Running == true' <<<"$inspection" >/dev/null || return 1
    mode=$(jq -r --arg name "$name" '.containers[$name].mode' "$readiness")
    case "$mode" in
      health)
        jq -e '.[0].State.Health.Status == "healthy"' <<<"$inspection" >/dev/null || return 1
        ;;
      tcp)
        network=$(jq -r --arg name "$name" '.containers[$name].network' "$readiness")
        port=$(jq -r --arg name "$name" '.containers[$name].port' "$readiness")
        podman run --rm --network "$network" "$probe_image" \
          busybox nc -z -w 3 "$name" "$port" >/dev/null 2>&1 || return 1
        ;;
      running)
        ;;
      *)
        die "unsupported readiness mode for $name: $mode"
        ;;
    esac
  done
}

check_no_egress() {
  local name network
  local -a blocked_networks=()

  for name in "${expected_names[@]}"; do
    while IFS= read -r network; do
      case "$network" in
        homelab-radicale|homelab-syncthing|homelab-vaultwarden|\
        homelab-supernote-edge|homelab-supernote-notelib-egress)
          blocked_networks+=("$network")
          ;;
      esac
    done < <(podman inspect "$name" | jq -r '.[0].NetworkSettings.Networks | keys[]')
  done

  ((${#blocked_networks[@]} > 0)) || return 0
  mapfile -t blocked_networks < <(printf '%s\n' "${blocked_networks[@]}" | sort -u)
  for network in "${blocked_networks[@]}"; do
    if podman run --rm --network "$network" "$probe_image" \
      sh -c 'busybox nc -z -w 3 1.1.1.1 443' >/dev/null 2>&1; then
      die "network permits external TCP access: $network"
    fi
  done
}

until check_runtime; do
  (( SECONDS < deadline )) || die "containers did not become ready within ${timeout_seconds}s"
  sleep 5
done

check_no_egress

assert_container_scope() {
  local actual expected
  actual=$(podman ps --format '{{.Names}}' | sort)
  expected=$(printf '%s\n' "${expected_names[@]}" | sort)
  [[ $actual == "$expected" ]] || {
    printf 'unexpected containers started by selected E2E scope\n' >&2
    printf '%s\n' 'expected:' "$expected" >&2
    printf '%s\n' 'actual:' "$actual" >&2
    return 1
  }
}

assert_container_scope

stable_ids=()
for name in "${expected_names[@]}"; do
  stable_ids+=("$(podman inspect --format '{{.Id}}' "$name")")
done
sleep 15
for index in "${!expected_names[@]}"; do
  name=${expected_names[$index]}
  inspection=$(podman inspect "$name") || die "container disappeared during stability check: $name"
  jq -e '.[0].State.Running == true' <<<"$inspection" >/dev/null || \
    die "container stopped during stability check: $name"
  current_id=$(jq -r '.[0].Id' <<<"$inspection")
  [[ $current_id == "${stable_ids[$index]}" ]] || \
    die "container restarted during stability check: $name"
done

if [[ $selector_mode == all ]]; then
  "$test_root/bin/security-audit"
fi
printf 'real Podman E2E passed: %s container(s)\n' "${#expected_names[@]}"
