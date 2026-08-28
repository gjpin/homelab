#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*" >&2
}

repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

host_arch() {
  local arch=${1:-$(uname -m)}
  case "$arch" in
    x86_64|amd64) printf '%s\n' amd64 ;;
    aarch64|arm64) printf '%s\n' arm64 ;;
    *) die "unsupported host architecture: $arch (supported architectures: amd64 and arm64)" ;;
  esac
}

require_pq_age_recipient() {
  local label=$1 recipient=$2
  [[ $recipient == age1pq1* ]] || die "$label must be an age post-quantum recipient (age1pq1...)"
}

require_subordinate_id_range() {
  local database=$1 user=$2
  [[ -r $database ]] || die "subordinate ID database is unavailable: $database"
  awk -F: -v user="$user" '
    $1 == user && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $3 >= 65536 { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$database" || die "$user has no valid subordinate ID range in $database"
}

load_site_config() {
  local root=${1:-$(repo_root)}
  local file="$root/config/site.env"
  local line key value
  [[ -r "$file" ]] || die "missing site configuration: $file"
  BASE_DOMAIN=
  TIMEZONE=
  HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID=
  BACKUP_S3_ENDPOINT=
  BACKUP_S3_REGION=
  BACKUP_S3_BUCKET=
  BACKUP_S3_PREFIX=
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    [[ $line == *=* ]] || die "invalid site configuration line: $line"
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      BASE_DOMAIN) BASE_DOMAIN=$value ;;
      TIMEZONE) TIMEZONE=$value ;;
      HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID) HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID=$value ;;
      BACKUP_S3_ENDPOINT) BACKUP_S3_ENDPOINT=$value ;;
      BACKUP_S3_REGION) BACKUP_S3_REGION=$value ;;
      BACKUP_S3_BUCKET) BACKUP_S3_BUCKET=$value ;;
      BACKUP_S3_PREFIX) BACKUP_S3_PREFIX=$value ;;
      *) die "unknown site configuration key: $key" ;;
    esac
  done <"$file"
  [[ ${BASE_DOMAIN:-} != "" && ${BASE_DOMAIN} != "example.invalid" ]] || die "BASE_DOMAIN is not configured"
  [[ $BASE_DOMAIN =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || die "BASE_DOMAIN is invalid"
  [[ ${TIMEZONE:-} =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$ ]] || die "TIMEZONE is invalid"
  [[ ${HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID:-} != "" && ${HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID} != "REPLACE_ME" ]] || die "HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID is not configured"
  [[ $HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID =~ ^[A-Za-z0-9._:+-]+$ ]] || die "HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID is invalid"
  [[ ${BACKUP_S3_ENDPOINT:-} =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?$ ]] || die "BACKUP_S3_ENDPOINT must be an HTTPS origin without a trailing slash"
  [[ $BACKUP_S3_ENDPOINT != "https://s3.example.invalid" ]] || die "BACKUP_S3_ENDPOINT is not configured"
  [[ ${BACKUP_S3_REGION:-} =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "BACKUP_S3_REGION is invalid"
  [[ ${BACKUP_S3_BUCKET:-} =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || die "BACKUP_S3_BUCKET is invalid"
  [[ $BACKUP_S3_BUCKET != "replace-me" ]] || die "BACKUP_S3_BUCKET is not configured"
  [[ ${BACKUP_S3_PREFIX:-} =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*[A-Za-z0-9]$ ]] || die "BACKUP_S3_PREFIX is invalid"
  [[ $BACKUP_S3_PREFIX != *'..'* && $BACKUP_S3_PREFIX != *'//'* ]] || die "BACKUP_S3_PREFIX contains an unsafe path component"
  export BASE_DOMAIN TIMEZONE HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID
  export BACKUP_S3_ENDPOINT BACKUP_S3_REGION BACKUP_S3_BUCKET BACKUP_S3_PREFIX
}
