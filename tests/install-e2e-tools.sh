#!/usr/bin/env bash
set -Eeuo pipefail

source_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$source_root/bin/lib.sh"
load_host_tools "$source_root/config/host-tools.env"

if ! command -v python3 >/dev/null 2>&1; then
  info "installing Fedora Python runtime for the E2E renderer"
  sudo rpm-ostree install --apply-live python3
fi
require_command python3

tool_dir="$HOME/.local/bin"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
install -d -m 0700 "$tool_dir"
export PATH="$tool_dir:$PATH"

case "$(uname -m)" in
  x86_64)
    age_archive=age-v1.3.1-linux-amd64.tar.gz
    age_sha256=bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377
    sops_binary="sops-${SOPS_RELEASE_TAG}.linux.amd64"
    sops_sha256=$SOPS_AMD64_BINARY_SHA256
    runner_binary="forgejo-runner-${FORGEJO_RUNNER_VERSION}-linux-amd64"
    runner_sha256=$FORGEJO_RUNNER_AMD64_BINARY_SHA256
    ;;
  aarch64)
    age_archive=age-v1.3.1-linux-arm64.tar.gz
    age_sha256=c6878a324421b69e3e20b00ba17c04bc5c6dab0030cfe55bf8f68fa8d9e9093a
    sops_binary="sops-${SOPS_RELEASE_TAG}.linux.arm64"
    sops_sha256=$SOPS_ARM64_BINARY_SHA256
    runner_binary="forgejo-runner-${FORGEJO_RUNNER_VERSION}-linux-arm64"
    runner_sha256=$FORGEJO_RUNNER_ARM64_BINARY_SHA256
    ;;
  *)
    printf 'unsupported E2E machine architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

curl --fail --location --proto '=https' --tlsv1.2 \
  --output "$tmp_dir/$age_archive" \
  "https://github.com/FiloSottile/age/releases/download/v1.3.1/$age_archive"
printf '%s  %s\n' "$age_sha256" "$tmp_dir/$age_archive" | sha256sum --check --status
tar --extract --gzip --file "$tmp_dir/$age_archive" --directory "$tmp_dir"
install -m 0755 \
  "$tmp_dir/age/age" \
  "$tmp_dir/age/age-keygen" \
  "$tmp_dir/age/age-inspect" \
  "$tool_dir/"

curl --fail --location --proto '=https' --tlsv1.2 \
  --output "$tmp_dir/$sops_binary" \
  "https://github.com/getsops/sops/releases/download/${SOPS_RELEASE_TAG}/$sops_binary"
printf '%s  %s\n' "$sops_sha256" "$tmp_dir/$sops_binary" | sha256sum --check --status
install -m 0755 "$tmp_dir/$sops_binary" "$tool_dir/sops"

curl --fail --location --proto '=https' --tlsv1.2 \
  --output "$tmp_dir/$runner_binary" \
  "https://code.forgejo.org/forgejo/runner/releases/download/${FORGEJO_RUNNER_RELEASE_TAG}/$runner_binary"
printf '%s  %s\n' "$runner_sha256" "$tmp_dir/$runner_binary" | sha256sum --check --status
install -m 0755 "$tmp_dir/$runner_binary" "$tool_dir/forgejo-runner"

age-keygen --version
sops --version --disable-version-check
forgejo-runner --version
