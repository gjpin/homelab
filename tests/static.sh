#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
containers="$root/quadlet/applications"

"$root/tests/architecture.sh"

rg -q 'age-keygen -pq -o' "$root/bin/bootstrap-host" || { printf 'host age identity is not post-quantum\n' >&2; exit 1; }
for package in \
  age ca-certificates container-selinux curl diffutils firewalld fuse-overlayfs \
  gettext-envsubst gawk git iproute jq libselinux-utils openssh-clients passt \
  podman policycoreutils python3 restic ripgrep shadow-utils systemd tar util-linux; do
  rg -q "^[[:space:]]+$package$" "$root/bin/bootstrap-host" || {
    printf 'Fedora package is missing from bootstrap: %s\n' "$package" >&2
    exit 1
  }
done
if rg -n '(^|/)(install-age|install-restic)$|install-age|install-restic' \
  --glob '!tests/static.sh' "$root/bin" "$root/README.md" "$root/docs"; then
  printf 'retired age/restic installers are still referenced\n' >&2
  exit 1
fi
[[ ! -e "$root/bin/install-age" && ! -e "$root/bin/install-restic" ]] || {
  printf 'retired age/restic installer files still exist\n' >&2
  exit 1
}
for mapping in \
  'rpm_arch=x86_64' \
  'rpm_arch=aarch64' \
  'sops-3.13.3-1.x86_64.rpm' \
  'sops-3.13.3-1.aarch64.rpm'; do
  rg -Fq "$mapping" "$root/bin/install-sops" || {
    printf 'missing SOPS RPM architecture mapping: %s\n' "$mapping" >&2
    exit 1
  }
done
for checksum in \
  f362eabc5b17b84894952fc57737eccf26ef8a4321453c165f4b1205b5544123 \
  0b3a519c93abaff3edfcaf8a16b19cd3b7cc935daf604999b3b52aac96e5770e; do
  rg -Fq "$checksum" "$root/bin/install-sops" || {
    printf 'missing SOPS RPM checksum: %s\n' "$checksum" >&2
    exit 1
  }
done
rg -q 'rpm -qip' "$root/bin/install-sops" || { printf 'SOPS RPM metadata is not validated\n' >&2; exit 1; }
rg -q 'dnf install -y "\$tmp_rpm"' "$root/bin/install-sops" || { printf 'SOPS RPM is not installed through DNF\n' >&2; exit 1; }
rg -q 'installed_version=.*%\{VERSION\}' "$root/bin/install-sops" || { printf 'installed SOPS version is not checked\n' >&2; exit 1; }
rg -q 'require_rpm_version age 1\.3\.0' "$root/bin/bootstrap-host" || { printf 'Fedora age minimum is not checked\n' >&2; exit 1; }
rg -q 'require_rpm_version restic 0\.19\.1' "$root/bin/bootstrap-host" || { printf 'Fedora restic minimum is not checked\n' >&2; exit 1; }
rg -q 'rm -f --' "$root/bin/bootstrap-host" || { printf 'legacy host binaries are not cleaned up\n' >&2; exit 1; }
rg -q 'require_command pasta' "$root/bin/bootstrap-host" || { printf 'rootless pasta preflight is missing\n' >&2; exit 1; }
rg -q 'require_command fuse-overlayfs' "$root/bin/bootstrap-host" || { printf 'rootless overlay preflight is missing\n' >&2; exit 1; }
rg -q 'require_command newuidmap' "$root/bin/bootstrap-host" || { printf 'newuidmap preflight is missing\n' >&2; exit 1; }
rg -q 'require_command newgidmap' "$root/bin/bootstrap-host" || { printf 'newgidmap preflight is missing\n' >&2; exit 1; }
rg -q -- '--add-subuids' "$root/bin/bootstrap-host" || { printf 'subuid provisioning is missing\n' >&2; exit 1; }
rg -q -- '--add-subgids' "$root/bin/bootstrap-host" || { printf 'subgid provisioning is missing\n' >&2; exit 1; }
rg -q '/etc/subuid' "$root/bin/bootstrap-host" || { printf 'subuid validation is missing\n' >&2; exit 1; }
rg -q '/etc/subgid' "$root/bin/bootstrap-host" || { printf 'subgid validation is missing\n' >&2; exit 1; }
rg -q 'require_command rg' "$root/bin/reconcile" || { printf 'reconciliation rg preflight is missing\n' >&2; exit 1; }
for command in fuse-overlayfs newgidmap newuidmap pasta; do
  rg -q "require_command $command" "$root/bin/verify-host-security" || {
    printf 'runtime rootless preflight is missing: %s\n' "$command" >&2
    exit 1
  }
done
rg -q 'require_subordinate_id_range /etc/subuid' "$root/bin/verify-host-security" || {
  printf 'runtime subuid validation is missing\n' >&2
  exit 1
}
rg -q 'require_subordinate_id_range /etc/subgid' "$root/bin/verify-host-security" || {
  printf 'runtime subgid validation is missing\n' >&2
  exit 1
}
rg -q '\-\-host-age-key' "$root/bin/bootstrap-host" || { printf 'host age identity cannot be restored during bootstrap\n' >&2; exit 1; }
rg -q 'qemu-user-binfmt.*qemu-user-static-x86' "$root/bin/bootstrap-host" || {
  printf 'ARM64 bootstrap does not install the required QEMU packages\n' >&2
  exit 1
}
rg -q 'systemctl enable --now systemd-binfmt' "$root/bin/bootstrap-host" || {
  printf 'ARM64 bootstrap does not enable systemd-binfmt\n' >&2
  exit 1
}
rg -q 'qemu-x86_64-static' "$root/bin/bootstrap-host" || {
  printf 'ARM64 bootstrap does not validate qemu-x86_64-static\n' >&2
  exit 1
}
rg -q '/proc/sys/fs/binfmt_misc/qemu-x86_64' "$root/bin/bootstrap-host" || {
  printf 'ARM64 bootstrap does not validate the x86_64 binfmt registration\n' >&2
  exit 1
}
rg -q 'qemu-x86_64-static' "$root/bin/verify-host-security" || {
  printf 'host security verification does not validate QEMU on ARM64\n' >&2
  exit 1
}
for unit in supernote-notelib supernote-service; do
  rg -q '^PodmanArgs=--arch=amd64 --image-volume=ignore$' \
    "$containers/supernote/$unit.container" || {
    printf 'Supernote unit does not force amd64: %s\n' "$unit" >&2
    exit 1
  }
done
rg -q 'podman pull --arch=amd64' "$root/bin/reconcile" || {
  printf 'reconciliation has no ARM64 Supernote pull override\n' >&2
  exit 1
}
rg -q 'require_pq_age_recipient "--host-recipient"' "$root/bin/init-secrets" || { printf 'host recipient is not checked as post-quantum\n' >&2; exit 1; }
rg -q 'require_pq_age_recipient "--operator-recipient"' "$root/bin/init-secrets" || { printf 'operator recipient is not checked as post-quantum\n' >&2; exit 1; }
rg -q 'fedora:44@sha256:[0-9a-f]{64}' "$root/.github/workflows/validate.yml" || {
  printf 'validation must use a digest-pinned Fedora 44 image\n' >&2
  exit 1
}

count=$(find "$containers" -name '*.container' -type f | wc -l | tr -d ' ')
[[ $count == 23 ]] || { printf 'expected 23 containers, found %s\n' "$count" >&2; exit 1; }

while IFS= read -r reference; do
  [[ -f "$root/quadlet/networks/$reference" ]] || { printf 'missing network unit: %s\n' "$reference" >&2; exit 1; }
done < <(rg --no-filename '^Network=.*\.network$' "$containers" | cut -d= -f2 | sort -u)

while IFS= read -r reference; do
  [[ -f "$root/quadlet/volumes/$reference" ]] || { printf 'missing volume unit: %s\n' "$reference" >&2; exit 1; }
done < <(rg --no-filename '^Volume=[^/:]+\.volume:' "$containers" | cut -d= -f2 | cut -d: -f1 | sort -u)

while IFS= read -r reference; do
  rg -q "replace_secret ${reference} " "$root/bin/render-config" || { printf 'secret is not provisioned: %s\n' "$reference" >&2; exit 1; }
done < <(rg --no-filename '^Secret=' "$containers" | cut -d= -f2 | cut -d, -f1 | sort -u)

[[ $(rg -l '^NoNewPrivileges=true$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must set NoNewPrivileges=true\n' >&2; exit 1; }
[[ $(rg -l '^DropCapability=all$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must drop the default capability set\n' >&2; exit 1; }
[[ $(rg -l '^ReadOnly=true$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must use a read-only root filesystem\n' >&2; exit 1; }
[[ $(rg -l '^ReadOnlyTmpfs=true$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must explicitly enable read-only tmpfs support\n' >&2; exit 1; }
[[ $(rg -l '^PodmanArgs=.*--image-volume=ignore$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must reject implicit anonymous image volumes\n' >&2; exit 1; }
[[ $(rg -l '^PidsLimit=1024$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must set the approved PID limit\n' >&2; exit 1; }
[[ $(rg -l '^PartOf=homelab-.*\.target$' "$containers" | wc -l | tr -d ' ') == 23 ]] || { printf 'every container must belong to an application target\n' >&2; exit 1; }

rootless_units=(
  anythingllm/anythingllm.container
  caddy/caddy.container
  docs-mcp/docs-mcp-server.container
  docs-mcp/docs-mcp-web.container
  docs-mcp/docs-mcp-worker.container
  forgejo/forgejo.container
  forgejo/forgejo-postgres.container
  homeassistant/homeassistant-mosquitto.container
  homeassistant/homeassistant-zigbee2mqtt.container
  immich/immich-machine-learning.container
  immich/immich-postgres.container
  immich/immich-valkey.container
  immich/immich-server.container
  radicale/radicale.container
  searxng/searxng-core.container
  searxng/searxng-valkey.container
  supernote/supernote-redis.container
  supernote/supernote-mariadb.container
  syncthing/syncthing.container
  vaultwarden/vaultwarden.container
)
for unit in "${rootless_units[@]}"; do
  rg -q '^User=' "$containers/$unit" || {
    printf 'rootless-capable container is missing an explicit User: %s\n' "$unit" >&2
    exit 1
  }
done
[[ $(rg -l '^User=' "$containers" | wc -l | tr -d ' ') == "${#rootless_units[@]}" ]] || {
  printf 'a container has an undocumented root user exception\n' >&2
  exit 1
}

if rg --no-filename '^AddCapability=' "$containers" | cut -d= -f2- | tr ' ' '\n' | \
  rg -v '^(NET_BIND_SERVICE|CHOWN|DAC_OVERRIDE|FOWNER|SETGID|SETUID)$'; then
  printf 'forbidden capability exception found\n' >&2
  exit 1
fi

security_labels=$(rg --no-filename '^SecurityLabelType=' "$containers" | sort)
[[ $security_labels == 'SecurityLabelType=container_device_t' ]] || {
  printf 'only Zigbee2MQTT may override the SELinux process domain\n' >&2
  exit 1
}
rg -q '^SecurityLabelType=container_device_t$' \
  "$containers/homeassistant/homeassistant-zigbee2mqtt.container" || {
  printf 'Zigbee2MQTT must use container_device_t\n' >&2
  exit 1
}

ports=$(rg --no-filename '^PublishPort=' "$containers" | sort)
expected=$'PublishPort=127.0.0.1:8443:443/tcp\nPublishPort=22000:22000/tcp\nPublishPort=22000:22000/udp'
[[ $ports == "$expected" ]] || { printf 'unexpected published ports:\n%s\n' "$ports" >&2; exit 1; }

if rg -n 'Privileged=true|Network=host|SecurityLabelDisable=true|SecurityLabelNested=true|SecurityLabelType=spc_t|SeccompProfile=unconfined|AutoUpdate=' "$containers"; then
  printf 'forbidden container setting found\n' >&2
  exit 1
fi

rg -q 'setsebool -P container_use_devices off' "$root/bin/bootstrap-host" || {
  printf 'bootstrap does not disable the global container device boolean\n' >&2
  exit 1
}
if rg -n 'setsebool .*container_use_devices (1|on)' "$root/bin"; then
  printf 'global container device access must never be enabled\n' >&2
  exit 1
fi
rg -q '^Requires=homelab-selinux-guard.service$' "$root/systemd/user/homelab-secrets.service" || {
  printf 'secret rendering must require the SELinux startup guard\n' >&2
  exit 1
}
rg -q 'bin/security-audit' "$root/bin/reconcile" || {
  printf 'reconciliation must run the runtime security audit\n' >&2
  exit 1
}

[[ -x "$root/bin/backup" && -x "$root/bin/restic" && -x "$root/bin/install-sops" ]] || {
  printf 'backup executables are not executable\n' >&2
  exit 1
}
rg -q '^restic_binary=\$\{HOMELAB_RESTIC_BIN:-/usr/bin/restic\}$' "$root/bin/restic" || {
  printf 'restic wrapper does not default to the Fedora package path\n' >&2
  exit 1
}
for setting in BACKUP_S3_ENDPOINT BACKUP_S3_REGION BACKUP_S3_BUCKET BACKUP_S3_PREFIX; do
  rg -q "^${setting}=" "$root/config/site.env" || {
    printf 'missing backup site setting: %s\n' "$setting" >&2
    exit 1
  }
done
for secret in s3_access_key_id s3_secret_access_key repository_password; do
  rg -q "^  ${secret}:" "$root/secrets/secrets.example.yaml" || {
    printf 'missing backup secret schema key: %s\n' "$secret" >&2
    exit 1
  }
done
rg -q 'homelab-operation\.lock' "$root/bin/backup" || { printf 'backup maintenance lock is missing\n' >&2; exit 1; }
rg -q 'homelab-operation\.lock' "$root/bin/reconcile" || { printf 'reconcile does not share the maintenance lock\n' >&2; exit 1; }
rg -q -- '--keep-daily 2 --keep-weekly 4 --keep-monthly 2 --prune' "$root/bin/backup" || {
  printf 'automatic backup retention policy is incorrect\n' >&2
  exit 1
}
rg -q '^OnCalendar=\*-\*-\* 03:00:00$' "$root/systemd/user/homelab-backup.timer" || {
  printf 'backup timer schedule is incorrect\n' >&2
  exit 1
}
rg -q '^Persistent=true$' "$root/systemd/user/homelab-backup.timer" || {
  printf 'backup timer must catch up missed runs\n' >&2
  exit 1
}
rg -q 'homelab-backup\.timer' "$root/bin/reconcile" || {
  printf 'reconciliation does not enable the backup timer\n' >&2
  exit 1
}
for guide in backups.md host-migration.md restore-volume.md; do
  [[ -f "$root/docs/$guide" ]] || { printf 'missing backup guide: %s\n' "$guide" >&2; exit 1; }
done
rg -q '/home/homelab/current/bin/restic init' "$root/README.md" || {
  printf 'initial installation does not initialize the restic repository\n' >&2
  exit 1
}

network_count=$(find "$root/quadlet/networks" -name '*.network' -type f | wc -l | tr -d ' ')
[[ $network_count == 17 ]] || { printf 'expected 17 networks, found %s\n' "$network_count" >&2; exit 1; }
[[ $(rg -l '^Options=isolate=true$' "$root/quadlet/networks" | wc -l | tr -d ' ') == 17 ]] || {
  printf 'every network must explicitly use bridge isolation\n' >&2
  exit 1
}
for backend in forgejo homeassistant immich searxng supernote; do
  rg -q '^Internal=true$' "$root/quadlet/networks/$backend.network" || {
    printf 'backend network is not internal: %s\n' "$backend" >&2
    exit 1
  }
  if rg -q "^Network=$backend.network$" "$containers/caddy/caddy.container"; then
    printf 'Caddy must not join backend network: %s\n' "$backend" >&2
    exit 1
  fi
  rg -q "^Network=$backend-edge.network$" "$containers/caddy/caddy.container" || {
    printf 'Caddy is missing edge network: %s\n' "$backend" >&2
    exit 1
  }
done

if rg -l --glob '*postgres.container' --glob '*mariadb.container' \
  --glob '*redis.container' --glob '*valkey.container' --glob '*mosquitto.container' \
  '^Network=.*-edge\.network$' "$containers"; then
  printf 'a database, cache, or MQTT container is attached to an edge network\n' >&2
  exit 1
fi
rg -q '^Network=immich-ml-egress.network$' \
  "$containers/immich/immich-machine-learning.container" || {
  printf 'Immich machine learning is missing its dedicated egress network\n' >&2
  exit 1
}
rg -q '^Network=supernote-notelib-egress.network$' \
  "$containers/supernote/supernote-notelib.container" || {
  printf 'Supernote notelib is missing its dedicated egress network\n' >&2
  exit 1
}

rg -q '^HOMEASSISTANT_TRUSTED_PROXY_SUBNET=10\.200\.12\.0/24$' "$root/bin/render-config" || {
  printf 'Home Assistant must trust its Caddy edge subnet\n' >&2
  exit 1
}

if rg --no-filename '^Image=' "$containers" | rg -v '\.build$' | rg -v '@sha256:[0-9a-f]{64}$'; then
  printf 'every upstream image must be pinned by digest\n' >&2
  exit 1
fi

if rg '^FROM ' "$root/images" | rg -v '@sha256:[0-9a-f]{64}([[:space:]]+AS[[:space:]]+.*)?$'; then
  printf 'every Containerfile base image must be pinned by digest\n' >&2
  exit 1
fi

printf 'static topology validation passed\n'
