#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/homelab-e2e-selection.XXXXXX")
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

fixture="$work_dir/repository"
mkdir -p "$fixture/bin" "$fixture/manifests" "$fixture/tests" \
  "$fixture/quadlet/applications/alpha" "$fixture/quadlet/applications/beta" \
  "$fixture/quadlet/applications/caddy" "$fixture/quadlet/builds" \
  "$fixture/images/caddy"
cp "$root/bin/lib.sh" "$fixture/bin/lib.sh"
cp "$root/bin/e2e-targets" "$fixture/bin/e2e-targets"
chmod +x "$fixture/bin/e2e-targets"

cat >"$fixture/manifests/applications.json" <<'EOF'
{
  "alpha": {"units": ["alpha.service"], "secrets": []},
  "beta": {"units": ["beta.service"], "secrets": []},
  "caddy": {"units": ["caddy.service", "caddy-build.service"], "secrets": []}
}
EOF
cat >"$fixture/tests/e2e-readiness.json" <<'EOF'
{
  "version": 1,
  "containers": {
    "alpha": {"mode": "running"},
    "beta": {"mode": "running"},
    "caddy": {"mode": "running"}
  }
}
EOF
printf 'ContainerName=alpha\n' >"$fixture/quadlet/applications/alpha/alpha.container"
printf 'ContainerName=beta\n' >"$fixture/quadlet/applications/beta/beta.container"
printf 'ContainerName=caddy\n' >"$fixture/quadlet/applications/caddy/caddy.container"
printf '[Build]\n' >"$fixture/quadlet/builds/caddy.build"
printf 'FROM scratch\n' >"$fixture/images/caddy/Containerfile"

git -C "$fixture" init -q
git -C "$fixture" config user.email e2e-selection@example.test
git -C "$fixture" config user.name e2e-selection
git -C "$fixture" add .
git -C "$fixture" commit -q -m base
base=$(git -C "$fixture" rev-parse HEAD)

assert_scope() {
  local expected=$1 description=$2 actual
  actual=$("$fixture/bin/e2e-targets" "$base" HEAD)
  [[ $actual == "$expected" ]] || {
    printf 'selection mismatch for %s: expected %q, got %q\n' \
      "$description" "$expected" "$actual" >&2
    exit 1
  }
}

assert_ci() {
  local description=$1 actual expected_line
  shift
  actual=$("$fixture/bin/e2e-targets" --format=ci "$base" HEAD)
  for expected_line in "$@"; do
    grep -Fxq -- "$expected_line" <<<"$actual" || {
      printf 'CI selection mismatch for %s: expected %q in:\n%s\n' \
        "$description" "$expected_line" "$actual" >&2
      exit 1
    }
  done
}

make_commit() {
  git -C "$fixture" add .
  git -C "$fixture" commit -q -m change
}

reset_fixture() {
  git -C "$fixture" checkout -q "$base"
  git -C "$fixture" clean -fdq
}

printf 'ContainerName=alpha-updated\n' >"$fixture/quadlet/applications/alpha/alpha.container"
make_commit
assert_scope alpha 'container change'
assert_ci 'container change' \
  'e2e_mode=workloads' 'e2e_workloads=alpha' 'build_images=' 'host_tools=false'
reset_fixture

mkdir -p "$fixture/quadlet/applications/gamma"
cat >"$fixture/manifests/applications.json" <<'EOF'
{
  "alpha": {"units": ["alpha.service"], "secrets": []},
  "beta": {"units": ["beta.service"], "secrets": []},
  "caddy": {"units": ["caddy.service", "caddy-build.service"], "secrets": []},
  "gamma": {"units": ["gamma.service"], "secrets": []}
}
EOF
cat >"$fixture/tests/e2e-readiness.json" <<'EOF'
{
  "version": 1,
  "containers": {
    "alpha": {"mode": "running"},
    "beta": {"mode": "running"},
    "caddy": {"mode": "running"},
    "gamma": {"mode": "running"}
  }
}
EOF
printf 'ContainerName=gamma\n' >"$fixture/quadlet/applications/gamma/gamma.container"
make_commit
assert_scope gamma 'new workload'
reset_fixture

sed -i 's/"alpha": {"mode": "running"}/"alpha": {"mode": "tcp", "network": "alpha", "port": 1}/' \
  "$fixture/tests/e2e-readiness.json"
make_commit
assert_scope alpha 'readiness metadata change'
reset_fixture

printf 'ContainerName=alpha-updated\n' >"$fixture/quadlet/applications/alpha/alpha.container"
printf 'ContainerName=beta-updated\n' >"$fixture/quadlet/applications/beta/beta.container"
make_commit
assert_scope $'alpha\nbeta' 'multiple workload changes'
reset_fixture

mkdir -p "$fixture/quadlet/networks"
printf '[Network]\n' >"$fixture/quadlet/networks/shared.network"
make_commit
assert_scope all 'global network change'
reset_fixture

mkdir -p "$fixture/quadlet/networks"
printf '[Network]\n' >"$fixture/quadlet/networks/alpha-edge.network"
make_commit
assert_scope alpha 'workload network change'
assert_ci 'workload network change' \
  'e2e_mode=workloads' 'e2e_workloads=alpha' 'build_images=' 'host_tools=false'
reset_fixture

mkdir -p "$fixture/quadlet/volumes"
printf '[Volume]\n' >"$fixture/quadlet/volumes/alpha-data.volume"
make_commit
assert_scope alpha 'workload volume change'
reset_fixture

mkdir -p "$fixture/docs"
printf 'documentation\n' >"$fixture/docs/change.md"
make_commit
assert_scope none 'documentation change'
assert_ci 'documentation change' \
  'e2e_mode=none' 'e2e_workloads=' 'build_images=' 'host_tools=false'
reset_fixture

mkdir -p "$fixture/.github/workflows"
printf 'name: Renovate\n' >"$fixture/.github/workflows/renovate.yml"
make_commit
assert_scope none 'Renovate workflow change'
assert_ci 'Renovate workflow change' \
  'e2e_mode=none' 'e2e_workloads=' 'build_images=' 'host_tools=false'
reset_fixture

printf '{}\n' >"$fixture/renovate.json"
make_commit
assert_scope none 'renovate.json change'
assert_ci 'renovate.json change' \
  'e2e_mode=none' 'e2e_workloads=' 'build_images=' 'host_tools=false'
reset_fixture

mkdir -p "$fixture/.github/workflows"
printf 'name: Validate\n' >"$fixture/.github/workflows/validate.yml"
make_commit
assert_scope none 'validate workflow change'
assert_ci 'validate workflow change' \
  'e2e_mode=none' 'e2e_workloads=' 'build_images=caddy' 'host_tools=true'
reset_fixture

printf 'FROM scratch\n# rebuild\n' >"$fixture/images/caddy/Containerfile"
make_commit
assert_scope caddy 'custom image change'
assert_ci 'custom image change' \
  'e2e_mode=workloads' 'e2e_workloads=caddy' 'build_images=caddy' 'host_tools=false'
reset_fixture

mkdir -p "$fixture/config"
printf 'SOPS_RELEASE_TAG=v1.0.0\n' >"$fixture/config/host-tools.env"
make_commit
assert_scope all 'host-tools metadata change'
assert_ci 'host-tools metadata change' \
  'e2e_mode=all' 'e2e_workloads=' 'build_images=caddy' 'host_tools=true'
reset_fixture

printf 'E2E selection tests passed\n'
