#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"

rg -q 'docker volume inspect' "$root/bin/backup" || die "backup does not inspect Docker volumes"
rg -q 'homelab_compose' "$root/bin/backup" || die "backup does not stop Compose projects"
rg -q 'podman' "$root/bin/backup" && die "backup still calls podman"
rg -q 'quadlet' "$root/bin/backup" && die "backup still references Quadlets"

printf 'backup script checks passed\n'
