#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Forgejo Runner E2E failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

[[ $EUID -eq 0 ]] || { printf 'Forgejo Runner E2E must run as root in the disposable machine\n' >&2; exit 1; }
root=${1:?usage: forgejo-runner-e2e.sh TEST_ROOT PRODUCTION_USER}
production_user=${2:?usage: forgejo-runner-e2e.sh TEST_ROOT PRODUCTION_USER}
# shellcheck source=/dev/null
source "$root/bin/lib.sh"
# shellcheck source=/dev/null
source "$root/bin/lib-forgejo-runner-host.sh"

runner_user=forgejo-runner
runner_home=/home/forgejo-runner
runner_secret=0123456789abcdef0123456789abcdef01234567
production_uid=$(id -u "$production_user")

for command in nft mkfs.xfs; do
  if ! command -v "$command" >/dev/null 2>&1; then
    rpm-ostree install --apply-live nftables xfsprogs
    break
  fi
done

if ! id "$runner_user" >/dev/null 2>&1; then
  useradd --create-home --home-dir "$runner_home" --shell /bin/bash "$runner_user"
fi
passwd --lock "$runner_user"
chmod 0700 "$runner_home"
if ! subordinate_id_ranges /etc/subuid "$runner_user" | grep -q .; then
  usermod --add-subuids 200000-265535 "$runner_user"
fi
if ! subordinate_id_ranges /etc/subgid "$runner_user" | grep -q .; then
  usermod --add-subgids 200000-265535 "$runner_user"
fi
require_matching_subordinate_id_ranges "$production_user"
require_matching_subordinate_id_ranges "$runner_user"
require_nonoverlapping_subordinate_id_ranges "$production_user" "$runner_user" /etc/subuid
require_nonoverlapping_subordinate_id_ranges "$production_user" "$runner_user" /etc/subgid
runner_uid=$(id -u "$runner_user")

install -m 0755 "/home/$production_user/.local/bin/forgejo-runner" /usr/local/bin/forgejo-runner
forgejo_runner_configure_storage "$runner_user" "$runner_home"
forgejo_runner_configure_user_slice "$runner_uid"
loginctl enable-linger "$runner_user"
systemctl start "user@${runner_uid}.service"
runner_systemctl=(runuser -u "$runner_user" -- env \
  HOME="$runner_home" XDG_RUNTIME_DIR="/run/user/$runner_uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$runner_uid/bus" systemctl --user)

install -d -m 0700 -o "$runner_user" -g "$runner_user" \
  "$runner_home/.config" "$runner_home/.config/forgejo-runner" \
  "$runner_home/.config/systemd" "$runner_home/.config/systemd/user"
install -m 0644 -o "$runner_user" -g "$runner_user" "$root/systemd/user/forgejo-runner.service" \
  "$root/systemd/user/forgejo-runner-prune.service" "$root/systemd/user/forgejo-runner-prune.timer" \
  "$runner_home/.config/systemd/user/"

test_forgejo_host=$(ip -4 route get 1.1.1.1 | awk '{ for (i=1; i<=NF; i++) if ($i == "src") { print $(i+1); exit } }')
[[ -n $test_forgejo_host ]] || die "cannot determine the E2E machine address"
FORGEJO_RUNNER_ALLOWED_TCP_PORT=3000
export FORGEJO_RUNNER_ALLOWED_TCP_PORT
install -d -m 0755 /etc/nftables
forgejo_runner_render_egress "$root/config/nftables/forgejo-runner-egress.nft" \
  /etc/nftables/homelab-forgejo-runner-egress.nft "$test_forgejo_host"
install -m 0644 "$root/systemd/system/homelab-forgejo-runner-egress.service" \
  /etc/systemd/system/homelab-forgejo-runner-egress.service
systemctl daemon-reload
systemctl enable homelab-forgejo-runner-egress.service
systemctl restart homelab-forgejo-runner-egress.service
nft list table inet homelab_runner_egress >/dev/null

production_podman=(runuser -u "$production_user" -- env HOME="/home/$production_user" XDG_RUNTIME_DIR="/run/user/$production_uid" podman)
for _ in {1..60}; do
  curl -fsS http://127.0.0.1:3000/api/healthz >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:3000/api/healthz >/dev/null
"${production_podman[@]}" exec forgejo forgejo admin user create \
  --username e2e --password e2e-forgejo-runner-password --email e2e@example.invalid \
  --admin --must-change-password=false >/dev/null
curl -fsS --user e2e:e2e-forgejo-runner-password \
  -H 'Content-Type: application/json' -d '{"name":"runner","private":true,"auto_init":true}' \
  http://127.0.0.1:3000/api/v1/user/repos >/dev/null
uuid=$(printf '%s' "$runner_secret" | "${production_podman[@]}" exec -i forgejo \
  forgejo forgejo-cli actions register --name homelab-runner --scope e2e --secret-stdin true | tr -d '\r\n')
validate_forgejo_runner_uuid "$uuid"

runner_config="$runner_home/.config/forgejo-runner/config.yaml"
# shellcheck disable=SC2016
sed "s#https://git\.\${BASE_DOMAIN}/#http://$test_forgejo_host:3000/#" \
  "$root/config/templates/forgejo-runner/config.yaml" >"$runner_config.template"
BASE_DOMAIN=e2e.test
FORGEJO_RUNNER_UUID=$uuid
FORGEJO_RUNNER_SECRET=$runner_secret
export BASE_DOMAIN FORGEJO_RUNNER_UUID FORGEJO_RUNNER_SECRET
# shellcheck disable=SC2016
envsubst '${BASE_DOMAIN} ${FORGEJO_RUNNER_UUID} ${FORGEJO_RUNNER_SECRET}' \
  <"$runner_config.template" >"$runner_config"
rm -f "$runner_config.template"
chown "$runner_user:$runner_user" "$runner_config"
chmod 0600 "$runner_config"

"${runner_systemctl[@]}" daemon-reload
"${runner_systemctl[@]}" enable --now podman.socket forgejo-runner-prune.timer forgejo-runner.service
"${runner_systemctl[@]}" is-active --quiet podman.socket forgejo-runner.service

workflow_repo=$(mktemp -d)
git clone --quiet http://e2e:e2e-forgejo-runner-password@127.0.0.1:3000/e2e/runner.git "$workflow_repo"
install -d "$workflow_repo/.forgejo/workflows"
sed "s/__PRODUCTION_UID__/$production_uid/g" \
  "$root/tests/fixtures/forgejo-runner/isolation.yml" \
  >"$workflow_repo/.forgejo/workflows/isolation.yml"
git -C "$workflow_repo" config user.name 'Forgejo Runner E2E'
git -C "$workflow_repo" config user.email e2e@example.invalid
git -C "$workflow_repo" add .forgejo/workflows/isolation.yml
git -C "$workflow_repo" commit --quiet -m 'add pinned runner isolation workflow'
git -C "$workflow_repo" push --quiet
rm -rf -- "$workflow_repo"

# shellcheck disable=SC2016
runner_podman=(runuser -u "$runner_user" -- \
  env HOME="$runner_home" XDG_RUNTIME_DIR="/run/user/$runner_uid" \
  bash -c 'cd "$HOME"; exec podman "$@"' bash)
observed_job=false
run_status=
for _ in {1..180}; do
  if "${runner_podman[@]}" ps --format '{{.Names}}' | grep -Eq '^FORGEJO-ACTIONS-TASK-'; then
    observed_job=true
    production_names=$("${production_podman[@]}" ps -a --format '{{.Names}}')
    ! grep -Eq '^FORGEJO-ACTIONS-TASK-' <<<"$production_names" || die "CI job appeared in production Podman"
  fi
  runs=$(curl -fsS --user e2e:e2e-forgejo-runner-password \
    http://127.0.0.1:3000/api/v1/repos/e2e/runner/actions/runs)
  run_status=$(jq -r '.workflow_runs[0].status // empty' <<<"$runs")
  [[ $run_status =~ ^(success|failure|cancelled)$ ]] && break
  sleep 2
done
[[ $observed_job == true ]] || die "Forgejo Runner E2E did not observe a runner-owned job container"
if [[ $run_status != success ]]; then
  job_id=$(curl -fsS --user e2e:e2e-forgejo-runner-password \
    http://127.0.0.1:3000/api/v1/repos/e2e/runner/actions/runs/1/jobs | jq -r '.[0].id // empty')
  if [[ -n $job_id ]]; then
    curl -fsS --user e2e:e2e-forgejo-runner-password \
      "http://127.0.0.1:3000/api/v1/repos/e2e/runner/actions/jobs/$job_id/logs" >&2 || true
  fi
  die "Forgejo Runner isolation workflow failed: status=$run_status"
fi
nft -a list chain inet homelab_runner_egress runner_egress_rules | \
  awk '/private_ipv4.*counter packets/ { for (i=1; i<=NF; i++) if ($i == "packets" && $(i+1) > 0) found=1 } END { exit(found ? 0 : 1) }' || \
  die "hostile workflow did not exercise the private-network egress denial"

for _ in {1..30}; do
  [[ -z $("${runner_podman[@]}" ps -aq) ]] && break
  sleep 1
done
[[ -z $("${runner_podman[@]}" ps -aq) ]] || die "Forgejo Runner left job containers behind"
[[ -z $("${runner_podman[@]}" network ls --format '{{.Name}}' | grep -E '^(FORGEJO-ACTIONS-TASK-|WORKFLOW-)' || true) ]] || \
  die "Forgejo Runner left a job network behind"

if runuser -u "$runner_user" -- fallocate -l 21G \
  "$(forgejo_runner_storage_path "$runner_home")/quota-probe" 2>/dev/null; then
  die "Forgejo Runner storage exceeded its 20 GiB capacity"
fi
rm -f "$(forgejo_runner_storage_path "$runner_home")/quota-probe"

install -m 0644 -o "$runner_user" -g "$runner_user" \
  "$root/tests/fixtures/forgejo-runner/forbidden-volume.yml" "$runner_home/forbidden-volume.yml"
# shellcheck disable=SC2016
if runuser -u "$runner_user" -- env HOME="$runner_home" XDG_RUNTIME_DIR="/run/user/$runner_uid" \
  DOCKER_HOST="unix:///run/user/$runner_uid/podman/podman.sock" \
  bash -c 'cd "$HOME"; exec forgejo-runner exec --config "$HOME/.config/forgejo-runner/config.yaml" --workflows "$HOME/forbidden-volume.yml"' \
  >/dev/null 2>&1; then
  die "Forgejo Runner accepted a forbidden host-volume workflow"
fi

info "Forgejo Runner smoke and adversarial Podman E2E passed"
