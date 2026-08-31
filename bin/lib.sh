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

validate_base_domain() {
  local value=${1:-}
  [[ $value != "" && $value != "example.invalid" ]] || die "site.base_domain is not configured"
  [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || die "site.base_domain is invalid"
}

validate_timezone() {
  local value=${1:-}
  [[ $value =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$ ]] || die "site.timezone is invalid"
}

validate_zigbee_serial() {
  local value=${1:-}
  [[ $value != "" && $value != "REPLACE_ME" ]] || die "site.homeassistant_zigbee_router_serial_id is not configured"
  [[ $value =~ ^[A-Za-z0-9._:+-]+$ ]] || die "site.homeassistant_zigbee_router_serial_id is invalid"
}

validate_backup_s3_endpoint() {
  local value=${1:-}
  [[ $value =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?$ ]] || \
    die "backup.s3_endpoint must be an HTTPS origin without a trailing slash"
  [[ $value != "https://s3.example.invalid" ]] || die "backup.s3_endpoint is not configured"
}

validate_backup_s3_region() {
  local value=${1:-}
  [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "backup.s3_region is invalid"
}

validate_backup_s3_bucket() {
  local value=${1:-}
  [[ $value =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || die "backup.s3_bucket is invalid"
  [[ $value != "replace-me" ]] || die "backup.s3_bucket is not configured"
}

validate_backup_s3_prefix() {
  local value=${1:-}
  [[ -z $value ]] && return 0
  [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*[A-Za-z0-9]$ ]] || die "backup.s3_prefix is invalid"
  [[ $value != *'..'* && $value != *'//'* ]] || die "backup.s3_prefix contains an unsafe path component"
}

apply_site_config() {
  local secrets_json=$1
  BASE_DOMAIN=$(jq -r '.site.base_domain // empty' <<<"$secrets_json")
  TIMEZONE=$(jq -r '.site.timezone // empty' <<<"$secrets_json")
  HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID=$(jq -r '.site.homeassistant_zigbee_router_serial_id // empty' <<<"$secrets_json")
  BACKUP_S3_ENDPOINT=$(jq -r '.backup.s3_endpoint // empty' <<<"$secrets_json")
  BACKUP_S3_REGION=$(jq -r '.backup.s3_region // empty' <<<"$secrets_json")
  BACKUP_S3_BUCKET=$(jq -r '.backup.s3_bucket // empty' <<<"$secrets_json")
  BACKUP_S3_PREFIX=$(jq -r '.backup.s3_prefix // empty' <<<"$secrets_json")
  validate_base_domain "$BASE_DOMAIN"
  validate_timezone "$TIMEZONE"
  validate_zigbee_serial "$HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID"
  validate_backup_s3_endpoint "$BACKUP_S3_ENDPOINT"
  validate_backup_s3_region "$BACKUP_S3_REGION"
  validate_backup_s3_bucket "$BACKUP_S3_BUCKET"
  validate_backup_s3_prefix "$BACKUP_S3_PREFIX"
  export BASE_DOMAIN TIMEZONE HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID
  export BACKUP_S3_ENDPOINT BACKUP_S3_REGION BACKUP_S3_BUCKET BACKUP_S3_PREFIX
}

load_site_config() {
  local root=${1:-$(repo_root)}
  local secrets_file="$root/secrets/secrets.sops.yaml"
  local secrets_json
  [[ -r $secrets_file ]] || die "missing encrypted secrets: $secrets_file"
  require_command jq
  require_command sops
  secrets_json=$(sops --decrypt --output-type json "$secrets_file")
  apply_site_config "$secrets_json"
  unset secrets_json
}
