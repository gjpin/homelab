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
releases_dir="$test_home/releases"
repo_dir="$test_home/git/repository"
current_link="$test_home/current"
log="$test_root/commands.log"
archive_tree="$test_root/archive"
old_release="$releases_dir/oldcommit"
new_release_name=newcommitnewcommitnewcommitnewcommitnewcommit

install -d "$fixture/bin" "$fake_bin" "$runtime_dir" "$state_dir" \
  "$repo_dir/.git" "$test_home/.ssh" \
  "$archive_tree/bin" "$archive_tree/manifests" \
  "$archive_tree/quadlet/applications/demo" \
  "$archive_tree/systemd/user" \
  "$old_release/bin" "$old_release/manifests" \
  "$old_release/quadlet/applications/demo" \
  "$old_release/systemd/user" \
  "$test_home/.config/containers/systemd" \
  "$test_home/.config/systemd/user"

cp "$source_root/bin/reconcile" "$source_root/bin/lib.sh" "$fixture/bin/"
chmod 0755 "$fixture/bin/reconcile"

printf 'ssh-ed25519 AAAA test\n' >"$test_home/.ssh/id_ed25519"
printf 'github.com ssh-ed25519 AAAA\n' >"$test_home/.ssh/known_hosts"
chmod 0600 "$test_home/.ssh/id_ed25519" "$test_home/.ssh/known_hosts"

cat >"$archive_tree/manifests/applications.json" <<'EOF'
{
  "demo": {"units": ["demo.service"], "secrets": []}
}
EOF
printf '[Unit]\nDescription=demo\n' >"$archive_tree/systemd/user/homelab-demo.target"
printf '[Container]\nContainerName=demo\n' >"$archive_tree/quadlet/applications/demo/demo.container"
cp "$archive_tree/manifests/applications.json" "$old_release/manifests/"
cp "$archive_tree/systemd/user/homelab-demo.target" "$old_release/systemd/user/"
cp "$archive_tree/quadlet/applications/demo/demo.container" "$old_release/quadlet/applications/demo/"

cat >"$archive_tree/bin/lib.sh" <<'EOF'
#!/usr/bin/env bash
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }
EOF
cp "$archive_tree/bin/lib.sh" "$old_release/bin/lib.sh"

for stub in validate fetch-assets verify-host-security migrate-databases security-audit; do
  cat >"$archive_tree/bin/$stub" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s %s\\n' "$stub" "\$*" >>"\$TEST_LOG"
exit 0
EOF
  chmod 0755 "$archive_tree/bin/$stub"
  cp "$archive_tree/bin/$stub" "$old_release/bin/$stub"
done

ln -sfn "$old_release" "$current_link"
printf 'oldcommit\n' >"$state_dir/deployed-commit"

cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == -C ]]; then
  shift 2
fi
printf 'git %s\n' "$*" >>"$TEST_LOG"
if [[ -n ${GIT_SSH_COMMAND:-} ]]; then
  printf 'GIT_SSH_COMMAND=%s\n' "$GIT_SSH_COMMAND" >>"$TEST_LOG"
fi
case "${1:-}" in
  fetch) exit 0 ;;
  rev-parse) printf '%s\n' "${TEST_TARGET_COMMIT:?}" ;;
  merge-base) exit 0 ;;
  archive) tar -c -C "$TEST_ARCHIVE_TREE" . ;;
  diff) printf '%s\n' "${TEST_CHANGED_PATH:-quadlet/applications/demo/demo.container}" ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == --user ]] && shift
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
case "${1:-}" in
  is-active)
    shift
    [[ ${1:-} == --quiet ]] && shift
    unit=${1:-}
    count_file="$TEST_ROOT/is-active.$unit"
    count=0
    [[ -f $count_file ]] && read -r count <"$count_file"
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    if [[ ${TEST_UNIT_FAIL:-0} == 1 ]]; then
      exit 1
    fi
    if ((count <= ${TEST_ACTIVE_AFTER_CALLS:-0})); then
      exit 1
    fi
    exit 0
    ;;
  start|restart|enable|disable|daemon-reload) exit 0 ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/podman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'podman %s\n' "$*" >>"$TEST_LOG"
case "${1:-}" in
  image) exit 0 ;;
  pull) exit 0 ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/flock" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'flock %s\n' "$*" >>"$TEST_LOG"
exit 0
EOF

cat >"$fake_bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$TEST_LOG"
exit 0
EOF

chmod 0755 "$fake_bin/git" "$fake_bin/systemctl" "$fake_bin/podman" \
  "$fake_bin/flock" "$fake_bin/sleep"

run_reconcile() {
  env PATH="$fake_bin:$PATH" HOME="$test_home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    HOMELAB_REPO_DIR="$repo_dir" \
    HOMELAB_RELEASES_DIR="$releases_dir" \
    HOMELAB_CURRENT_LINK="$current_link" \
    HOMELAB_STATE_DIR="$state_dir" \
    HOMELAB_UNIT_READY_TIMEOUT="${HOMELAB_UNIT_READY_TIMEOUT:-5}" \
    HOMELAB_UNIT_READY_INTERVAL="${HOMELAB_UNIT_READY_INTERVAL:-0}" \
    TEST_LOG="$log" TEST_ROOT="$test_root" \
    TEST_ARCHIVE_TREE="$archive_tree" \
    TEST_TARGET_COMMIT="${TEST_TARGET_COMMIT:?}" \
    TEST_CHANGED_PATH="${TEST_CHANGED_PATH:-quadlet/applications/demo/demo.container}" \
    TEST_ACTIVE_AFTER_CALLS="${TEST_ACTIVE_AFTER_CALLS:-0}" \
    TEST_UNIT_FAIL="${TEST_UNIT_FAIL:-0}" \
    "$fixture/bin/reconcile"
}

: >"$log"
TEST_TARGET_COMMIT=oldcommit run_reconcile >/dev/null
rg -Fq 'git fetch --prune origin +refs/heads/main:refs/remotes/origin/main' "$log"
rg -Fq 'git rev-parse refs/remotes/origin/main' "$log"
rg -Fq "GIT_SSH_COMMAND=ssh -i $test_home/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$test_home/.ssh/known_hosts" "$log"

: >"$log"
rm -f "$test_root"/is-active.*
TEST_TARGET_COMMIT=$new_release_name TEST_ACTIVE_AFTER_CALLS=2 run_reconcile >/dev/null
rg -q '^sleep 0$' "$log" || {
  printf 'reconcile did not wait for Notify=healthy units to become active\n' >&2
  exit 1
}
[[ $(readlink "$current_link") == "$releases_dir/$new_release_name" ]] || {
  printf 'current symlink was not switched to the new release\n' >&2
  exit 1
}
read -r deployed <"$state_dir/deployed-commit"
[[ $deployed == "$new_release_name" ]] || {
  printf 'deployed-commit was not updated\n' >&2
  exit 1
}

# A change that maps to no application (for example a CI workflow edit)
# must still wait for every declared unit before the runtime security
# audit: the homelab-secrets.service restart bounces units that
# Requires= it even when no application target is restarted.
ln -sfn "$old_release" "$current_link"
printf 'oldcommit\n' >"$state_dir/deployed-commit"
: >"$log"
rm -f "$test_root"/is-active.*
TEST_TARGET_COMMIT=$new_release_name \
  TEST_CHANGED_PATH='.github/workflows/renovate.yml' \
  TEST_ACTIVE_AFTER_CALLS=2 run_reconcile >/dev/null
rg -q '^sleep 0$' "$log" || {
  printf 'no-application change skipped waiting for declared units\n' >&2
  exit 1
}
[[ $(readlink "$current_link") == "$releases_dir/$new_release_name" ]] || {
  printf 'current symlink was not switched after a no-application change\n' >&2
  exit 1
}
read -r deployed <"$state_dir/deployed-commit"
[[ $deployed == "$new_release_name" ]] || {
  printf 'deployed-commit was not updated after a no-application change\n' >&2
  exit 1
}

ln -sfn "$old_release" "$current_link"
printf 'oldcommit\n' >"$state_dir/deployed-commit"
: >"$log"
rm -f "$test_root"/is-active.*
if TEST_TARGET_COMMIT=$new_release_name TEST_UNIT_FAIL=1 \
  HOMELAB_UNIT_READY_TIMEOUT=0 run_reconcile >/dev/null 2>&1; then
  printf 'reconcile succeeded while a unit stayed inactive\n' >&2
  exit 1
fi
[[ $(readlink "$current_link") == "$old_release" ]] || {
  printf 'failed activation did not restore the prior current symlink\n' >&2
  exit 1
}
read -r deployed <"$state_dir/deployed-commit"
[[ $deployed == oldcommit ]] || {
  printf 'failed activation overwrote deployed-commit\n' >&2
  exit 1
}

printf 'reconcile tests passed\n'
