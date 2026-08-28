#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"

assert_arch() {
  local input=$1 expected=$2 actual
  actual=$(host_arch "$input")
  [[ $actual == "$expected" ]] || die "host_arch $input returned $actual, expected $expected"
}

assert_arch x86_64 amd64
assert_arch amd64 amd64
assert_arch aarch64 arm64
assert_arch arm64 arm64

for unsupported in i686 riscv64; do
  if error=$(host_arch "$unsupported" 2>&1); then
    die "host_arch accepted unsupported architecture: $unsupported"
  fi
  [[ $error == *"unsupported host architecture: $unsupported"* ]] || \
    die "host_arch did not clearly reject unsupported architecture: $unsupported"
done

printf 'host architecture validation passed\n'
