#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

source_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$source_root/bin/lib.sh"

usage() {
  cat <<'EOF'
Usage: tests/e2e.sh [--workload NAME ... | --container NAME]

Run the Docker Compose E2E suite. With no selector, every workload is started.
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
require_command docker
require_command jq
require_command sops

manifest="$source_root/manifests/applications.json"
readiness="$source_root/tests/e2e-readiness.json"
jq -e 'type == "object" and length > 0' "$manifest" >/dev/null
jq -e '.version == 1 and (.containers | type == "object")' "$readiness" >/dev/null

test_parent=$(mktemp -d "${TMPDIR:-/tmp}/homelab-e2e.XXXXXX")
test_root="$test_parent/repository"
sops_key_file=
cleanup_done=false
started_apps=()

# Invoked by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
  local status=$? app
  [[ $cleanup_done == true ]] && return
  cleanup_done=true
  set +e
  if ((status != 0)); then
    printf '\nE2E failed; collecting runtime diagnostics\n' >&2
    docker ps -a --format 'table {{.Names}}\t{{.Status}}' >&2
    docker compose ls >&2
    while IFS= read -r name; do
      [[ -n $name ]] || continue
      printf '\n----- docker logs %s -----\n' "$name" >&2
      docker logs --tail 80 "$name" >&2 || true
    done < <(docker ps -a --format '{{.Names}}')
  fi
  for app in "${started_apps[@]}"; do
    HOMELAB_RELEASE_ROOT=$test_root HOMELAB_STATE_DIR=$test_parent/state \
      HOMELAB_RENDERED=$test_parent/state/rendered \
      "$test_root/bin/lib.sh" >/dev/null 2>&1
    HOMELAB_RELEASE_ROOT=$test_root \
    HOMELAB_STATE_DIR=$test_parent/state \
    HOMELAB_RENDERED=$test_parent/state/rendered \
      docker compose --project-name "homelab-$app" --file "$test_root/compose/$app/compose.yaml" \
        down --volumes --remove-orphans >/dev/null 2>&1
  done
  while IFS= read -r network; do
    docker network rm "$network" >/dev/null 2>&1
  done < <(jq -r 'keys[]' "$test_root/manifests/networks.json" 2>/dev/null)
  [[ -z ${sops_key_file:-} ]] || rm -f -- "$sops_key_file"
  rm -rf -- "$test_parent"
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

install -d -m 0700 "$test_root"
cp -a "$source_root/." "$test_root/"
install -d -m 0700 "$test_parent/state" "$test_parent/keys"
export HOME=$test_parent/home
export HOMELAB_STATE_DIR=$test_parent/state
export HOMELAB_RENDERED=$test_parent/state/rendered
export HOMELAB_RELEASE_ROOT=$test_root
export HOMELAB_SKIP_RUNNER_AUDIT=1
install -d -m 0700 "$HOME"

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
site:
  base_domain: e2e.test
  timezone: Europe/Lisbon
  homeassistant_zigbee_router_serial_id: e2e-fixture
backup:
  s3_endpoint: https://s3.e2e.test
  s3_region: us-east-1
  s3_bucket: homelab-e2e
  s3_prefix: e2e
  s3_access_key_id: e2e-access-key
  s3_secret_access_key: e2e-secret-key
  repository_password: e2e-repository-password-0123456789
caddy:
  cloudflare_api_token: e2e-cloudflare-token
  bookmarks_password_hash: e2e-bookmarks-hash
forgejo:
  database_password: e2e-forgejo-password
  runner_secret: 0123456789abcdef0123456789abcdef01234567
  runner_uuid: 01234567-89ab-cdef-0123-456789abcdef
homeassistant:
  mosquitto_password: e2e-mosquitto-password
immich:
  database_password: e2e-immich-password
radicale:
  htpasswd_record: 'admin:$2y$05$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'
searxng:
  secret_key: e2e-searxng-secret-key
vaultwarden:
  admin_token_hash: e2e-vaultwarden-admin-token
EOF

age-keygen -pq -o "$test_parent/keys/host.txt" >/dev/null
age-keygen -pq -o "$test_parent/keys/operator.txt" >/dev/null
host_recipient=$(age-keygen -y "$test_parent/keys/host.txt")
operator_recipient=$(age-keygen -y "$test_parent/keys/operator.txt")
cat "$test_parent/keys/host.txt" "$test_parent/keys/operator.txt" >"$test_parent/keys/keys.txt"
chmod 0600 "$test_parent/keys/keys.txt"
sops_key_file="$HOME/.config/sops/age/keys.txt"
install -d -m 0700 "$(dirname -- "$sops_key_file")"
install -m 0600 "$test_parent/keys/keys.txt" "$sops_key_file"
export SOPS_AGE_KEY_FILE="$test_parent/keys/keys.txt"
cat >"$test_root/.sops.yaml" <<EOF
creation_rules:
  - path_regex: ^secrets/.*\\.sops\\.yaml$
    age: ${host_recipient},${operator_recipient}
EOF
sops --encrypt \
  --config /dev/null \
  --age "$host_recipient,$operator_recipient" \
  --input-type yaml \
  --output-type yaml \
  "$test_root/secrets/e2e-plaintext.yaml" \
  >"$test_root/secrets/secrets.sops.yaml"
rm -f -- "$test_root/secrets/e2e-plaintext.yaml"

python3 - "$test_root/compose/homeassistant/compose.yaml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "image: ghcr.io/koenkk/zigbee2mqtt:2.14.1@sha256:fef0de769dcd04c27b3a6d277b61046eb96284bdd4198dcb1687c3a01b3020f3",
    "image: localhost/homelab/e2e-zigbee2mqtt",
)
lines = []
skip_devices = False
for line in text.splitlines(True):
    if line.strip() == "devices:":
        skip_devices = True
        continue
    if skip_devices:
        if line.startswith("      - "):
            continue
        skip_devices = False
    if "group_add:" in line or "- dialout" in line:
        continue
    if "/run/udev:" in line:
        continue
    if "zigbee-router:/dev/ttyACM0" in line:
        continue
    lines.append(line)
path.write_text("".join(lines))
PY
python3 - "$test_root/compose/syncthing/compose.yaml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = [line for line in path.read_text().splitlines(True) if "22000:22000" not in line and line.strip() != "ports:"]
path.write_text("".join(lines))
PY
python3 - "$test_root/compose/immich/compose.yaml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "IGNORE_DATABASE_FSTYPE" not in text:
    text = text.replace("POSTGRES_INITDB_ARGS: --data-checksums",
                        "POSTGRES_INITDB_ARGS: --data-checksums\n      IGNORE_DATABASE_FSTYPE: \"true\"")
    path.write_text(text)
PY
python3 - "$test_root/compose/forgejo/compose.yaml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "INSTALL_LOCK" not in text:
    text = text.replace(
        'FORGEJO__actions__DEFAULT_ACTIONS_URL: https://data.forgejo.org',
        'FORGEJO__actions__DEFAULT_ACTIONS_URL: https://data.forgejo.org\n      FORGEJO__security__INSTALL_LOCK: "true"',
    )
    path.write_text(text)
PY

docker build --pull --file "$test_root/tests/fixtures/zigbee2mqtt/Containerfile" \
  --tag localhost/homelab/e2e-zigbee2mqtt \
  "$test_root/tests/fixtures/zigbee2mqtt"
docker build --file "$test_root/images/caddy/Containerfile" --tag localhost/homelab/caddy \
  "$test_root/images/caddy"

"$test_root/bin/render-config"
"$test_root/bin/ensure-networks" "$test_root"
# Fixture serial path is not a real device; keep the rendered tree usable.
rm -f -- "$HOMELAB_STATE_DIR/zigbee-router"

mapfile -t apps < <(jq -r 'keys[]' "$manifest")
case "$selector_mode" in
  all) selected_apps=("${apps[@]}") ;;
  workload)
    selected_apps=()
    for workload in "${selected_workloads[@]}"; do
      jq -e --arg workload "$workload" 'has($workload)' "$manifest" >/dev/null || \
        die "unknown workload: $workload"
      selected_apps+=("$workload")
    done
    ;;
  container)
    selected_apps=()
    while IFS= read -r app; do
      if jq -e --arg app "$app" --arg name "$selector" \
        '.[$app].containers | index($name) != null' "$manifest" >/dev/null; then
        selected_apps+=("$app")
      fi
    done < <(printf '%s\n' "${apps[@]}")
    ((${#selected_apps[@]} > 0)) || die "unknown container: $selector"
    ;;
esac

if printf '%s\n' "${selected_apps[@]}" | grep -Fxq caddy; then
  :
else
  selected_apps+=(caddy)
fi

for app in "${selected_apps[@]}"; do
  info "starting $app"
  started_apps+=("$app")
  homelab_compose "$app" up -d --remove-orphans --pull missing
done

expected_names=()
for app in "${selected_apps[@]}"; do
  while IFS= read -r name; do
    expected_names+=("$name")
  done < <(jq -r --arg app "$app" '.[$app].containers[]' "$manifest")
done

deadline=$((SECONDS + 300))
for name in "${expected_names[@]}"; do
  mode=$(jq -r --arg name "$name" '.containers[$name].mode // "running"' "$readiness")
  while true; do
    running=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || printf 'false')
    if [[ $running == true ]]; then
      case "$mode" in
        running) break ;;
        health)
          health=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || printf 'none')
          [[ $health == healthy || $health == none ]] && break
          ;;
        tcp)
          network=$(jq -r --arg name "$name" '.containers[$name].network' "$readiness")
          port=$(jq -r --arg name "$name" '.containers[$name].port' "$readiness")
          if docker run --rm --network "$network" docker.io/library/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b \
            sh -c "nc -z $name $port"; then
            break
          fi
          ;;
      esac
    fi
    if ((SECONDS >= deadline)); then
      docker logs --tail 80 "$name" >&2 || true
      die "container did not become ready: $name"
    fi
    sleep 3
  done
done

HOMELAB_SKIP_RUNNER_AUDIT=1 "$test_root/bin/security-audit"
info "E2E passed"
