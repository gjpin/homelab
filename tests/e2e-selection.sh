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
  "$fixture/quadlet/applications/alpha" "$fixture/quadlet/applications/beta"
cp "$root/bin/lib.sh" "$fixture/bin/lib.sh"
cp "$root/bin/e2e-targets" "$fixture/bin/e2e-targets"
chmod +x "$fixture/bin/e2e-targets"

cat >"$fixture/manifests/applications.json" <<'EOF'
{
  "alpha": {"units": ["alpha.service"], "secrets": []},
  "beta": {"units": ["beta.service"], "secrets": []}
}
EOF
cat >"$fixture/tests/e2e-readiness.json" <<'EOF'
{
  "version": 1,
  "containers": {
    "alpha": {"mode": "running"},
    "beta": {"mode": "running"}
  }
}
EOF
printf 'ContainerName=alpha\n' >"$fixture/quadlet/applications/alpha/alpha.container"
printf 'ContainerName=beta\n' >"$fixture/quadlet/applications/beta/beta.container"

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

make_commit() {
  git -C "$fixture" add .
  git -C "$fixture" commit -q -m change
}

printf 'ContainerName=alpha-updated\n' >"$fixture/quadlet/applications/alpha/alpha.container"
make_commit
assert_scope alpha 'container change'
git -C "$fixture" checkout -q "$base"

mkdir -p "$fixture/quadlet/applications/gamma"
cat >"$fixture/manifests/applications.json" <<'EOF'
{
  "alpha": {"units": ["alpha.service"], "secrets": []},
  "beta": {"units": ["beta.service"], "secrets": []},
  "gamma": {"units": ["gamma.service"], "secrets": []}
}
EOF
cat >"$fixture/tests/e2e-readiness.json" <<'EOF'
{
  "version": 1,
  "containers": {
    "alpha": {"mode": "running"},
    "beta": {"mode": "running"},
    "gamma": {"mode": "running"}
  }
}
EOF
printf 'ContainerName=gamma\n' >"$fixture/quadlet/applications/gamma/gamma.container"
make_commit
assert_scope gamma 'new workload'
git -C "$fixture" checkout -q "$base"

sed -i 's/"alpha": {"mode": "running"}/"alpha": {"mode": "tcp", "network": "alpha", "port": 1}/' \
  "$fixture/tests/e2e-readiness.json"
make_commit
assert_scope alpha 'readiness metadata change'
git -C "$fixture" checkout -q "$base"

printf 'ContainerName=alpha-updated\n' >"$fixture/quadlet/applications/alpha/alpha.container"
printf 'ContainerName=beta-updated\n' >"$fixture/quadlet/applications/beta/beta.container"
make_commit
assert_scope $'alpha\nbeta' 'multiple workload changes'
git -C "$fixture" checkout -q "$base"

mkdir -p "$fixture/quadlet/networks"
printf '[Network]\n' >"$fixture/quadlet/networks/shared.network"
make_commit
assert_scope all 'global network change'
git -C "$fixture" checkout -q "$base"

mkdir -p "$fixture/docs"
printf 'documentation\n' >"$fixture/docs/change.md"
make_commit
assert_scope none 'documentation change'

printf 'E2E selection tests passed\n'
