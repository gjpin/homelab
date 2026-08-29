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
  amd64) expected_sha256=$SOPS_AMD64_RPM_SHA256 ;;
  arm64) expected_sha256=$SOPS_ARM64_RPM_SHA256 ;;
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

printf 'host-tool installation and SOPS functional tests passed: %s (%s)\n' "$SOPS_VERSION" "$arch"
