#!/usr/bin/env bash
set -Eeuo pipefail

tool_dir="$HOME/.local/bin"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
install -d -m 0700 "$tool_dir"

case "$(uname -m)" in
  x86_64)
    age_archive=age-v1.3.1-linux-amd64.tar.gz
    age_sha256=bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377
    sops_binary=sops-v3.13.3.linux.amd64
    sops_sha256=e5bec3346a873ae91d8715505f3e698c1aad962aff462a080e40f25fde17fef6b
    ;;
  aarch64)
    age_archive=age-v1.3.1-linux-arm64.tar.gz
    age_sha256=c6878a324421b69e3e20b00ba17c04bc5c6dab0030cfe55bf8f68fa8d9e9093a
    sops_binary=sops-v3.13.3.linux.arm64
    sops_sha256=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77
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
  "https://github.com/getsops/sops/releases/download/v3.13.3/$sops_binary"
printf '%s  %s\n' "$sops_sha256" "$tmp_dir/$sops_binary" | sha256sum --check --status
install -m 0755 "$tmp_dir/$sops_binary" "$tool_dir/sops"

age-keygen --version
sops --version
