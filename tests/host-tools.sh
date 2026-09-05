#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { printf 'host-tools test must run as root inside its disposable Fedora container\n' >&2; exit 1; }

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"
load_host_tools "$root/config/host-tools.env"
require_command cmp

arch=$(host_arch)
case "$arch" in
  amd64)
    expected_sha256=$SOPS_AMD64_RPM_SHA256
    expected_runner_sha256=$FORGEJO_RUNNER_AMD64_BINARY_SHA256
    ;;
  arm64)
    expected_sha256=$SOPS_ARM64_RPM_SHA256
    expected_runner_sha256=$FORGEJO_RUNNER_ARM64_BINARY_SHA256
    ;;
esac

install -d -m 0755 /usr/local/libexec
install -m 0755 "$root/bin/install-sops" /usr/local/libexec/homelab-install-sops
/usr/local/libexec/homelab-install-sops "$root/config/host-tools.env"
/usr/local/libexec/homelab-install-sops "$root/config/host-tools.env" >/dev/null

installed_version=$(rpm -q --queryformat '%{VERSION}' sops)
[[ $installed_version == "$SOPS_VERSION" ]] || {
  printf 'unexpected SOPS version: %s (expected %s)\n' "$installed_version" "$SOPS_VERSION" >&2
  exit 1
}
rpm -q sops >/dev/null

install -m 0755 "$root/bin/install-forgejo-runner" /usr/local/libexec/homelab-install-forgejo-runner
/usr/local/libexec/homelab-install-forgejo-runner "$root/config/host-tools.env"
/usr/local/libexec/homelab-install-forgejo-runner "$root/config/host-tools.env" >/dev/null

[[ -x /usr/local/bin/forgejo-runner ]] || {
  printf 'forgejo-runner executable was not installed\n' >&2
  exit 1
}
installed_runner_output=$(/usr/local/bin/forgejo-runner --version)
installed_runner_version=$(awk '{print $NF}' <<<"$installed_runner_output" | sed 's/^v//')
[[ $installed_runner_version == "$FORGEJO_RUNNER_VERSION" ]] || {
  printf 'unexpected forgejo-runner version: %s (expected %s)\n' \
    "$installed_runner_version" "$FORGEJO_RUNNER_VERSION" >&2
  exit 1
}
/usr/local/bin/forgejo-runner --help >/dev/null

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
age-keygen -pq -o "$test_dir/age-key.txt" >/dev/null 2>&1
recipient=$(age-keygen -y "$test_dir/age-key.txt")
printf 'creation_rules:\n  - path_regex: .*\n    age: %s\n' "$recipient" >"$test_dir/.sops.yaml"
printf 'value: host-tool-test\n' >"$test_dir/plain.yaml"
(
  cd -- "$test_dir"
  SOPS_AGE_KEY_FILE="$test_dir/age-key.txt" /usr/bin/sops \
    --encrypt --age "$recipient" --input-type yaml --output-type yaml \
    plain.yaml >encrypted.yaml
  SOPS_AGE_KEY_FILE="$test_dir/age-key.txt" /usr/bin/sops \
    --decrypt --input-type yaml --output-type yaml \
    encrypted.yaml >decrypted.yaml
)
cmp -s "$test_dir/plain.yaml" "$test_dir/decrypted.yaml" || {
  printf 'SOPS post-quantum encrypt/decrypt round trip failed\n' >&2
  exit 1
}

installed_evr=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' sops)
bad_config="$test_dir/host-tools-bad.env"
bad_sha256=0000000000000000000000000000000000000000000000000000000000000000
sed "s/$expected_sha256/$bad_sha256/" "$root/config/host-tools.env" >"$bad_config"
if /usr/local/libexec/homelab-install-sops "$bad_config" >/dev/null 2>&1; then
  printf 'SOPS installer accepted a bad checksum\n' >&2
  exit 1
fi
[[ $(rpm -q --queryformat '%{VERSION}-%{RELEASE}' sops) == "$installed_evr" ]] || {
  printf 'SOPS changed after checksum validation failed\n' >&2
  exit 1
}

bad_runner_config="$test_dir/host-tools-bad-runner.env"
sed "s/$expected_runner_sha256/$bad_sha256/" "$root/config/host-tools.env" >"$bad_runner_config"
if /usr/local/libexec/homelab-install-forgejo-runner "$bad_runner_config" >/dev/null 2>&1; then
  printf 'Forgejo Runner installer accepted a bad checksum\n' >&2
  exit 1
fi
current_runner_output=$(/usr/local/bin/forgejo-runner --version)
[[ $current_runner_output == "$installed_runner_output" ]] || {
  printf 'forgejo-runner changed after checksum validation failed\n' >&2
  exit 1
}

runner_before_sha=$(sha256sum /usr/local/bin/forgejo-runner | awk '{print $1}')
mock_bin="$test_dir/mock-bin"
install -d -m 0755 "$mock_bin"

cat >"$mock_bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'riscv64\n'
EOF
chmod 0755 "$mock_bin/uname"
if PATH="$mock_bin:$PATH" /usr/local/libexec/homelab-install-forgejo-runner \
  "$root/config/host-tools.env" >/dev/null 2>&1; then
  printf 'Forgejo Runner installer accepted an unsupported architecture\n' >&2
  exit 1
fi
rm -f "$mock_bin/uname"

cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 22
EOF
chmod 0755 "$mock_bin/curl"
if PATH="$mock_bin:$PATH" /usr/local/libexec/homelab-install-forgejo-runner \
  "$root/config/host-tools.env" >/dev/null 2>&1; then
  printf 'Forgejo Runner installer accepted a failed download\n' >&2
  exit 1
fi
rm -f "$mock_bin/curl"

fake_runner="$test_dir/forgejo-runner-0.0.1"
cat >"$fake_runner" <<'EOF'
#!/usr/bin/env bash
printf 'forgejo-runner version v0.0.1\n'
EOF
chmod 0755 "$fake_runner"
fake_sha=$(sha256sum "$fake_runner" | awk '{print $1}')
downgrade_config="$test_dir/host-tools-downgrade.env"
sed \
  -e 's/^FORGEJO_RUNNER_RELEASE_TAG=.*/FORGEJO_RUNNER_RELEASE_TAG=v0.0.1/' \
  -e "s/^FORGEJO_RUNNER_AMD64_BINARY_SHA256=.*/FORGEJO_RUNNER_AMD64_BINARY_SHA256=$fake_sha/" \
  -e "s/^FORGEJO_RUNNER_ARM64_BINARY_SHA256=.*/FORGEJO_RUNNER_ARM64_BINARY_SHA256=$fake_sha/" \
  "$root/config/host-tools.env" >"$downgrade_config"
cat >"$mock_bin/curl" <<EOF
#!/usr/bin/env bash
output=
while ((\$#)); do
  if [[ \$1 == --output ]]; then output=\$2; shift 2; else shift; fi
done
cp '$fake_runner' "\$output"
EOF
chmod 0755 "$mock_bin/curl"
if PATH="$mock_bin:$PATH" /usr/local/libexec/homelab-install-forgejo-runner \
  "$downgrade_config" >/dev/null 2>&1; then
  printf 'Forgejo Runner installer accepted a downgrade\n' >&2
  exit 1
fi

[[ $(sha256sum /usr/local/bin/forgejo-runner | awk '{print $1}') == "$runner_before_sha" ]] || {
  printf 'Forgejo Runner installer did not preserve the installed binary after failure\n' >&2
  exit 1
}
[[ $(stat -c %a /usr/local/bin/forgejo-runner) == 755 ]] || {
  printf 'Forgejo Runner executable permissions are invalid\n' >&2
  exit 1
}

printf 'host-tool installation, SOPS, and Forgejo Runner functional tests passed: sops=%s runner=%s (%s)\n' \
  "$SOPS_VERSION" "$FORGEJO_RUNNER_VERSION" "$arch"
