#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { printf 'host-tools test must run as root\n' >&2; exit 1; }

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"
load_host_tools "$root/config/host-tools.env"
require_command cmp
: "${AGE_VERSION:?}" "${RESTIC_VERSION:?}" "${SOPS_VERSION:?}" "${FORGEJO_RUNNER_VERSION:?}"

install -d -m 0755 /usr/local/lib/homelab
install -m 0755 "$root/bin/install-age" /usr/local/lib/homelab/install-age
install -m 0755 "$root/bin/install-restic" /usr/local/lib/homelab/install-restic
install -m 0755 "$root/bin/install-sops" /usr/local/lib/homelab/install-sops
install -m 0755 "$root/bin/install-forgejo-runner" /usr/local/lib/homelab/install-forgejo-runner

/usr/local/lib/homelab/install-age "$root/config/host-tools.env"
/usr/local/lib/homelab/install-age "$root/config/host-tools.env" >/dev/null
/usr/local/lib/homelab/install-restic "$root/config/host-tools.env"
/usr/local/lib/homelab/install-restic "$root/config/host-tools.env" >/dev/null
/usr/local/lib/homelab/install-sops "$root/config/host-tools.env"
/usr/local/lib/homelab/install-sops "$root/config/host-tools.env" >/dev/null
/usr/local/lib/homelab/install-forgejo-runner "$root/config/host-tools.env"
/usr/local/lib/homelab/install-forgejo-runner "$root/config/host-tools.env" >/dev/null

age_version=$(age --version | awk '{print $NF}' | sed 's/^v//')
[[ $age_version == "$AGE_VERSION" ]] || die "unexpected age version: $age_version"
restic_version=$(restic version | awk '{print $2}')
[[ $restic_version == "$RESTIC_VERSION" ]] || die "unexpected restic version: $restic_version"
sops_version=$(sops --version --disable-version-check | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {print $i; exit}}')
[[ $sops_version == "$SOPS_VERSION" ]] || die "unexpected SOPS version: $sops_version"
runner_version=$(forgejo-runner --version | awk '{print $NF}' | sed 's/^v//')
[[ $runner_version == "$FORGEJO_RUNNER_VERSION" ]] || die "unexpected forgejo-runner version: $runner_version"

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
age-keygen -pq -o "$test_dir/age-key.txt" >/dev/null 2>&1
recipient=$(age-keygen -y "$test_dir/age-key.txt")
printf 'value: host-tool-test\n' >"$test_dir/plain.yaml"
(
  cd -- "$test_dir"
  SOPS_AGE_KEY_FILE="$test_dir/age-key.txt" sops \
    --encrypt --age "$recipient" --input-type yaml --output-type yaml \
    --config /dev/null \
    plain.yaml >encrypted.yaml
  SOPS_AGE_KEY_FILE="$test_dir/age-key.txt" sops \
    --decrypt --input-type yaml --output-type yaml \
    --config /dev/null \
    encrypted.yaml >decrypted.yaml
)
cmp -s "$test_dir/plain.yaml" "$test_dir/decrypted.yaml" || die "SOPS post-quantum encrypt/decrypt round trip failed"

bad_config="$test_dir/host-tools-bad.env"
bad_sha256=0000000000000000000000000000000000000000000000000000000000000000
sed "s/$SOPS_AMD64_BINARY_SHA256/$bad_sha256/;s/$SOPS_ARM64_BINARY_SHA256/$bad_sha256/" \
  "$root/config/host-tools.env" >"$bad_config"
if /usr/local/lib/homelab/install-sops "$bad_config" >/dev/null 2>&1; then
  die "SOPS installer accepted a bad checksum"
fi

printf 'host-tools checks passed\n'
