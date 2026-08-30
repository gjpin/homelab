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

unquote_env_value() {
  local value=$1
  case "$value" in
    \"*\") value=${value:1:${#value}-2} ;;
    \'*\') value=${value:1:${#value}-2} ;;
  esac
  printf '%s' "$value"
}

rewrite_legacy_forgejo_tree() {
  local mountpoint=$1 app_ini tmp_ini
  [[ -n $mountpoint && -d $mountpoint && $mountpoint != / ]] || die "unsafe Forgejo tree: ${mountpoint:-}"
  [[ -d $mountpoint/gitea ]] || return 0
  if [[ -f $mountpoint/gitea/conf/app.ini ]]; then
    mkdir -p "$mountpoint/custom/conf"
    app_ini="$mountpoint/gitea/conf/app.ini"
    tmp_ini="$app_ini.rewritten"
    sed \
      -e 's#/data/#/var/lib/gitea/#g' \
      -e 's#\([[:space:]=]\)/data$#\1/var/lib/gitea#' \
      "$app_ini" >"$tmp_ini"
    mv "$tmp_ini" "$app_ini"
    mv "$app_ini" "$mountpoint/custom/conf/app.ini"
    rmdir "$mountpoint/gitea/conf" 2>/dev/null || true
  fi
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

load_host_tools() {
  local file=${1:-$(repo_root)/config/host-tools.env}
  local line key value
  [[ -r $file ]] || die "missing host tools metadata: $file"
  SOPS_RELEASE_TAG=
  SOPS_AMD64_RPM_SHA256=
  SOPS_AMD64_BINARY_SHA256=
  SOPS_ARM64_RPM_SHA256=
  SOPS_ARM64_BINARY_SHA256=
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    [[ $line == *=* ]] || die "invalid host tools metadata line: $line"
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      SOPS_RELEASE_TAG) [[ -z $SOPS_RELEASE_TAG ]] || die "duplicate host tools metadata key: $key"; SOPS_RELEASE_TAG=$value ;;
      SOPS_AMD64_RPM_SHA256) [[ -z $SOPS_AMD64_RPM_SHA256 ]] || die "duplicate host tools metadata key: $key"; SOPS_AMD64_RPM_SHA256=$value ;;
      SOPS_AMD64_BINARY_SHA256) [[ -z $SOPS_AMD64_BINARY_SHA256 ]] || die "duplicate host tools metadata key: $key"; SOPS_AMD64_BINARY_SHA256=$value ;;
      SOPS_ARM64_RPM_SHA256) [[ -z $SOPS_ARM64_RPM_SHA256 ]] || die "duplicate host tools metadata key: $key"; SOPS_ARM64_RPM_SHA256=$value ;;
      SOPS_ARM64_BINARY_SHA256) [[ -z $SOPS_ARM64_BINARY_SHA256 ]] || die "duplicate host tools metadata key: $key"; SOPS_ARM64_BINARY_SHA256=$value ;;
      *) die "unknown host tools metadata key: $key" ;;
    esac
  done <"$file"
  [[ $SOPS_RELEASE_TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "SOPS release tag is invalid: $SOPS_RELEASE_TAG"
  for value in "$SOPS_AMD64_RPM_SHA256" "$SOPS_AMD64_BINARY_SHA256" \
    "$SOPS_ARM64_RPM_SHA256" "$SOPS_ARM64_BINARY_SHA256"; do
    [[ $value =~ ^[0-9a-f]{64}$ ]] || die "host tools metadata contains an invalid SHA-256 checksum"
  done
  SOPS_VERSION=${SOPS_RELEASE_TAG#v}
  export SOPS_RELEASE_TAG SOPS_VERSION SOPS_AMD64_RPM_SHA256 SOPS_AMD64_BINARY_SHA256
  export SOPS_ARM64_RPM_SHA256 SOPS_ARM64_BINARY_SHA256
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
