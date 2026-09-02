#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
containers="$root/quadlet/applications"
workflows="$root/.github/workflows"
# shellcheck source=/dev/null
source "$root/bin/lib.sh"

require_command jq

"$root/tests/architecture.sh"
"$root/tests/selinux-policy.sh"
"$root/tests/zigbee-udev.sh"

load_host_tools "$root/config/host-tools.env"
[[ -f "$root/config/host-tools.env" ]] || { printf 'host tools metadata is missing\n' >&2; exit 1; }
for field in \
  SOPS_RELEASE_TAG SOPS_AMD64_RPM_SHA256 SOPS_AMD64_BINARY_SHA256 \
  SOPS_ARM64_RPM_SHA256 SOPS_ARM64_BINARY_SHA256; do
  rg -q "^${field}=" "$root/config/host-tools.env" || {
    printf 'host tools metadata is missing: %s\n' "$field" >&2
    exit 1
  }
done

rg -q 'age-keygen -pq -o' "$root/bin/bootstrap-host" || { printf 'host age identity is not post-quantum\n' >&2; exit 1; }
for package in \
  age ca-certificates checkpolicy container-selinux curl diffutils firewalld fuse-overlayfs \
  gettext-envsubst gawk git iproute jq libselinux-utils openssh-clients passt \
  podman policycoreutils python3 restic ripgrep shadow-utils systemd tar util-linux \
  xfsprogs; do
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
  "rpm_file=\"sops-\${version}-1.\${rpm_arch}.rpm\"" \
  "releases/download/\${release_tag}/\${rpm_file}"; do
  rg -Fq "$mapping" "$root/bin/install-sops" || {
    printf 'missing SOPS installer mapping: %s\n' "$mapping" >&2
    exit 1
  }
done
rg -q 'rpm -qip' "$root/bin/install-sops" || { printf 'SOPS RPM metadata is not validated\n' >&2; exit 1; }
rg -q 'dnf install -y "\$tmp_rpm"' "$root/bin/install-sops" || { printf 'SOPS RPM is not installed through DNF\n' >&2; exit 1; }
rg -q 'installed_version=.*%\{VERSION\}' "$root/bin/install-sops" || { printf 'installed SOPS version is not checked\n' >&2; exit 1; }
rg -q 'refusing to downgrade SOPS' "$root/bin/install-sops" || { printf 'SOPS installer does not reject downgrades\n' >&2; exit 1; }
rg -q 'sops --version --disable-version-check' "$root/bin/install-sops" || {
  printf 'SOPS installer must not let sops --version phone home\n' >&2
  exit 1
}
rg -q 'sops --version --disable-version-check' "$root/bin/status" || {
  printf 'status must not let sops --version phone home\n' >&2
  exit 1
}
rg -q 'sops --version --disable-version-check' "$root/tests/install-e2e-tools.sh" || {
  printf 'E2E SOPS install must not let sops --version phone home\n' >&2
  exit 1
}
rg -q 'install -m 0755 "\$root/bin/install-sops" /usr/local/libexec/homelab-install-sops' "$root/bin/bootstrap-host" || {
  printf 'bootstrap does not install the fixed SOPS updater\n' >&2
  exit 1
}
for unit in homelab-host-tools-update.service homelab-host-tools-update.timer; do
  [[ -f "$root/systemd/system/$unit" ]] || { printf 'missing host-tools system unit: %s\n' "$unit" >&2; exit 1; }
done
rg -q '^ExecStart=/usr/local/libexec/homelab-install-sops ' \
  "$root/systemd/system/homelab-host-tools-update.service" || {
  printf 'host-tools service does not use the fixed installer\n' >&2
  exit 1
}
if rg -n 'ExecStart=.*(%h/current/bin|/home/homelab/current/bin|/current/bin)' \
  "$root/systemd/system/homelab-host-tools-update.service"; then
  printf 'host-tools service executes mutable Git content as root\n' >&2
  exit 1
fi
rg -q '^OnCalendar=\*-\*-\* 02:00:00$' "$root/systemd/system/homelab-host-tools-update.timer" || {
  printf 'host-tools timer is not scheduled daily\n' >&2
  exit 1
}
rg -q '^Persistent=true$' "$root/systemd/system/homelab-host-tools-update.timer" || {
  printf 'host-tools timer must catch up missed runs\n' >&2
  exit 1
}
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
rg -q '\-\-no-data-disk' "$root/bin/bootstrap-host" || { printf 'bootstrap cannot skip an external storage disk\n' >&2; exit 1; }
rg -q '\-\-data-disk' "$root/bin/bootstrap-host" || { printf 'bootstrap cannot select an external storage disk\n' >&2; exit 1; }
rg -q '\-\-format-data-disk' "$root/bin/bootstrap-host" || { printf 'bootstrap cannot format an external storage disk\n' >&2; exit 1; }
rg -q 'homelab_storage_setup' "$root/bin/bootstrap-host" || { printf 'bootstrap does not configure Podman storage\n' >&2; exit 1; }
rg -q 'HOMELAB_STORAGE_FSTAB_MARKER="# homelab-podman-storage"' "$root/bin/lib-host-storage.sh" || {
  printf 'storage fstab marker is missing\n' >&2
  exit 1
}
rg -q 'x-systemd.automount' "$root/bin/lib-host-storage.sh" || {
  printf 'storage mount is not configured to automount\n' >&2
  exit 1
}
rg -q 'RequiresMountsFor=' "$root/bin/lib-host-storage.sh" || {
  printf 'user instance does not wait for Podman storage\n' >&2
  exit 1
}
rg -q 'nofail' "$root/bin/lib-host-storage.sh" && {
  printf 'storage mount must not use nofail\n' >&2
  exit 1
}
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
rg -q 'require_pq_age_recipient "--host-recipient"' "$root/bin/init-secrets" || { printf 'host recipient is not checked as post-quantum\n' >&2; exit 1; }
rg -q 'require_pq_age_recipient "--operator-recipient"' "$root/bin/init-secrets" || { printf 'operator recipient is not checked as post-quantum\n' >&2; exit 1; }
rg -qF 'sops --config /dev/null --age' "$root/bin/init-secrets" || {
  printf 'init-secrets PQ probe uses the repository .sops.yaml\n' >&2
  exit 1
}
rg -qF 'sops --config /dev/null --age "$recipients"' "$root/bin/init-secrets" || {
  printf 'init-secrets encrypt uses the repository .sops.yaml\n' >&2
  exit 1
}
rg -q 'fedora:44@sha256:[0-9a-f]{64}' "$root/.github/workflows/validate.yml" || {
  printf 'validation must use a digest-pinned Fedora 44 image\n' >&2
  exit 1
}
rg -q 'bin/e2e-targets --format=ci' "$root/.github/workflows/validate.yml" || {
  printf 'validation must select CI scope from the Git diff\n' >&2
  exit 1
}
rg -q '^    needs: \[select, validate\]$' "$root/.github/workflows/validate.yml" || {
  printf 'e2e must not wait on host-tools when selecting affected workloads\n' >&2
  exit 1
}

count=$(find "$containers" -name '*.container' -type f | wc -l | tr -d ' ')
manifest_container_count=$(jq '[.[] .units[] | select(endswith(".service")) | select(endswith("-build.service") | not)] | length' \
  "$root/manifests/applications.json")
[[ $count == "$manifest_container_count" ]] || {
  printf 'manifest declares %s containers, found %s\n' "$manifest_container_count" "$count" >&2
  exit 1
}

while IFS= read -r unit; do
  app=$(basename -- "$(dirname -- "$unit")")
  service="$(basename -- "$unit" .container).service"
  jq -e --arg app "$app" --arg service "$service" \
    '.[$app].units | index($service) != null' "$root/manifests/applications.json" >/dev/null || {
    printf 'container is missing from the workload manifest: %s\n' "$unit" >&2
    exit 1
  }
done < <(find "$containers" -name '*.container' -type f | sort)

while IFS= read -r app; do
  [[ -f "$root/systemd/user/homelab-$app.target" ]] || {
    printf 'workload is missing its systemd target: %s\n' "$app" >&2
    exit 1
  }
done < <(jq -r 'keys[]' "$root/manifests/applications.json")

readiness="$root/tests/e2e-readiness.json"
jq -e '.version == 1 and (.containers | type == "object")' "$readiness" >/dev/null || {
  printf 'E2E readiness metadata is invalid\n' >&2
  exit 1
}
readiness_count=$(jq '.containers | length' "$readiness")
[[ $readiness_count == "$count" ]] || {
  printf 'E2E readiness metadata covers %s containers, expected %s\n' "$readiness_count" "$count" >&2
  exit 1
}
while IFS= read -r unit; do
  file=$(find "$containers" -name "${unit%.service}.container" -type f -print -quit)
  name=$(sed -n 's/^ContainerName=//p' "$file")
  jq -e --arg name "$name" '.containers | has($name)' "$readiness" >/dev/null || {
    printf 'container has no E2E readiness entry: %s\n' "$name" >&2
    exit 1
  }
  mode=$(jq -r --arg name "$name" '.containers[$name].mode' "$readiness")
  case "$mode" in
    health)
      rg -q '^HealthCmd=' "$file" || {
        printf 'health readiness requires HealthCmd: %s\n' "$file" >&2
        exit 1
      }
      ;;
    tcp)
      jq -e --arg name "$name" \
        '.containers[$name].network | type == "string" and length > 0' "$readiness" >/dev/null || {
        printf 'TCP readiness is missing a network: %s\n' "$name" >&2
        exit 1
      }
      jq -e --arg name "$name" \
        '.containers[$name].port | type == "number" and . >= 1 and . <= 65535' "$readiness" >/dev/null || {
        printf 'TCP readiness has an invalid port: %s\n' "$name" >&2
        exit 1
      }
      ;;
    running) ;;
    *)
      printf 'unknown E2E readiness mode for %s: %s\n' "$name" "$mode" >&2
      exit 1
      ;;
  esac
done < <(jq -r '[.[] .units[] | select(endswith(".service")) | select(endswith("-build.service") | not)][]' \
  "$root/manifests/applications.json")

while IFS= read -r reference; do
  [[ -f "$root/quadlet/networks/$reference" ]] || { printf 'missing network unit: %s\n' "$reference" >&2; exit 1; }
done < <(rg --no-filename '^Network=.*\.network$' "$containers" | cut -d= -f2 | sort -u)

while IFS= read -r reference; do
  [[ -f "$root/quadlet/volumes/$reference" ]] || { printf 'missing volume unit: %s\n' "$reference" >&2; exit 1; }
done < <(rg --no-filename '^Volume=[^/:]+\.volume:' "$containers" | cut -d= -f2 | cut -d: -f1 | sort -u)

while IFS= read -r reference; do
  rg -q "replace_secret ${reference} " "$root/bin/render-config" || { printf 'secret is not provisioned: %s\n' "$reference" >&2; exit 1; }
done < <(rg --no-filename '^Secret=' "$containers" | cut -d= -f2 | cut -d, -f1 | sort -u)

[[ $(rg -l '^NoNewPrivileges=true$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must set NoNewPrivileges=true\n' >&2; exit 1; }
[[ $(rg -l '^DropCapability=all$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must drop the default capability set\n' >&2; exit 1; }
[[ $(rg -l '^ReadOnly=true$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must use a read-only root filesystem\n' >&2; exit 1; }
[[ $(rg -l '^ReadOnlyTmpfs=true$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must explicitly enable read-only tmpfs support\n' >&2; exit 1; }
[[ $(rg -l '^PodmanArgs=.*--image-volume=ignore$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must reject implicit anonymous image volumes\n' >&2; exit 1; }
[[ $(rg -l '^PidsLimit=1024$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must set the approved PID limit\n' >&2; exit 1; }
[[ $(rg -l '^RunInit=true$' "$containers" | wc -l | tr -d ' ') == 13 ]] || { printf 'every compatible container must set RunInit=true\n' >&2; exit 1; }
rg -q '^RunInit=false$' "$containers/homeassistant/homeassistant.container" || {
  printf 'homeassistant must set RunInit=false so s6-overlay stays PID 1\n' >&2
  exit 1
}
rg -q '^RunInit=false$' "$containers/homeassistant/homeassistant-zigbee2mqtt.container" || {
  printf 'zigbee2mqtt must set RunInit=false; non-root cannot exec /run/podman-init\n' >&2
  exit 1
}
rg -q '^GroupAdd=keep-groups$' "$containers/homeassistant/homeassistant-zigbee2mqtt.container" || {
  printf 'zigbee2mqtt must keep host groups for coordinator access\n' >&2
  exit 1
}
[[ $(rg -l '^PartOf=homelab-.*\.target$' "$containers" | wc -l | tr -d ' ') == 15 ]] || { printf 'every container must belong to an application target\n' >&2; exit 1; }

rootless_units=(
  caddy/caddy.container
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
rg -q 'install-selinux-policy' "$root/bin/bootstrap-host" || {
  printf 'bootstrap does not install the Caddy HTTPS proxy SELinux module\n' >&2
  exit 1
}
rg -q 'selinux/\*\.te' "$root/bin/bootstrap-host" || {
  printf 'bootstrap does not install every SELinux module in selinux/\n' >&2
  exit 1
}
rg -q 'install-zigbee-udev' "$root/bin/bootstrap-host" || {
  printf 'bootstrap does not install the Zigbee coordinator udev rule\n' >&2
  exit 1
}
rg -q 'gpasswd --delete "\$runtime_user" root' "$root/bin/install-zigbee-udev" || {
  printf 'Zigbee udev installer does not drop accidental root-group membership\n' >&2
  exit 1
}
rg -q 'systemctl stop caddy-https-proxy.service caddy-https-proxy.socket' "$root/bin/bootstrap-host" || {
  printf 'bootstrap cannot replace an already-installed Caddy HTTPS proxy\n' >&2
  exit 1
}
rg -q 'allow systemd_socket_proxyd_t http_port_t:tcp_socket \{ name_bind name_connect \};' \
  "$root/selinux/caddy-https-proxy.te" || {
  printf 'Caddy HTTPS proxy SELinux module does not allow 443 bind and 8443 connect\n' >&2
  exit 1
}
rg -q 'typeattribute container_device_t container_net_domain;' \
  "$root/selinux/zigbee2mqtt-network.te" || {
  printf 'Zigbee2MQTT SELinux module does not grant container_net_domain\n' >&2
  exit 1
}
if rg -n 'permissive |unconfined_|spc_t' "$root/selinux"; then
  printf 'SELinux policy must not add permissive or unconfined exceptions\n' >&2
  exit 1
fi
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
rg -q 'bin/migrate-databases' "$root/bin/reconcile" || {
  printf 'reconciliation must run the automated database migration tool\n' >&2
  exit 1
}
rg -q 'HOMELAB_OPERATION_LOCK_HELD=1' "$root/bin/reconcile" || {
  printf 'reconciliation must mark the maintenance lock as held for migrate-databases\n' >&2
  exit 1
}
rg -q 'restore_prior_release' "$root/bin/reconcile" || {
  printf 'reconciliation must restore the prior current symlink on activation failure\n' >&2
  exit 1
}
rg -Fq 'tar -x -p -C "$release"' "$root/bin/reconcile" || {
  printf 'release extract must preserve Git file modes for non-root bind mounts\n' >&2
  exit 1
}
[[ $(rg -F --count '.[$app].units[] | select(endswith("-build.service") | not)' "$root/bin/reconcile") == 2 ]] || {
  printf 'reconciliation must ignore oneshot image builds in repair and activation checks\n' >&2
  exit 1
}
rg -q '^Volume=%t/homelab/rendered/caddy/Caddyfile:' "$containers/caddy/caddy.container" || {
  printf 'Caddy must mount a rendered Caddyfile readable by the non-root image user\n' >&2
  exit 1
}
rg -Fq 'cp -- "$root/config/templates/caddy/Caddyfile" "$rendered/caddy/Caddyfile"' \
  "$root/bin/render-config" || {
  printf 'render-config must install the Caddyfile next to other rendered files\n' >&2
  exit 1
}
rg -Fq 'find "$rendered" -type f -exec chmod 0444 {} +' "$root/bin/render-config" || {
  printf 'rendered files must be world-readable for non-root container users\n' >&2
  exit 1
}
rg -Fq 'rm -rf -- "$rendered"' "$root/bin/render-config" || {
  printf 'render-config must replace the 0444 rendered tree on each run\n' >&2
  exit 1
}
while IFS= read -r build; do
  rg -q '^RemainAfterExit=yes$' "$build" || {
    printf 'image build unit must remain active after a successful build: %s\n' "$build" >&2
    exit 1
  }
done < <(find "$root/quadlet/builds" -name '*.build' -type f | sort)

[[ -x "$root/bin/backup" && -x "$root/bin/restic" && -x "$root/bin/install-sops" && \
  -x "$root/bin/install-selinux-policy" && -x "$root/bin/install-zigbee-udev" && \
  -x "$root/bin/migrate-databases" && -x "$root/bin/migrate-postgres" && \
  -x "$root/bin/migrate-mariadb" && -x "$root/bin/decommission-supernote" ]] || {
  printf 'required executables are not executable\n' >&2
  exit 1
}
rg -q '^restic_binary=\$\{HOMELAB_RESTIC_BIN:-/usr/bin/restic\}$' "$root/bin/restic" || {
  printf 'restic wrapper does not default to the Fedora package path\n' >&2
  exit 1
}
[[ ! -e $root/config/site.env ]] || {
  printf 'config/site.env must not exist; site settings belong in secrets/secrets.sops.yaml\n' >&2
  exit 1
}
rg -qF '"base_domain": base_domain' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt site.base_domain\n' >&2
  exit 1
}
rg -qF '"timezone": timezone' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt site.timezone\n' >&2
  exit 1
}
rg -qF '"homeassistant_zigbee_router_serial_id": zigbee_serial' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt site.homeassistant_zigbee_router_serial_id\n' >&2
  exit 1
}
rg -qF '"s3_endpoint": backup_s3_endpoint' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt backup.s3_endpoint\n' >&2
  exit 1
}
rg -qF '"s3_region": backup_s3_region' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt backup.s3_region\n' >&2
  exit 1
}
rg -qF '"s3_bucket": backup_s3_bucket' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt backup.s3_bucket\n' >&2
  exit 1
}
rg -qF '"s3_prefix": backup_s3_prefix' "$root/bin/init-secrets" || {
  printf 'init-secrets does not encrypt backup.s3_prefix\n' >&2
  exit 1
}
rg -q 'apply_site_config' "$root/bin/render-config" || {
  printf 'render-config does not load site identity from SOPS\n' >&2
  exit 1
}
rg -q 'apply_site_config' "$root/bin/restic" || {
  printf 'restic wrapper does not load site identity from SOPS\n' >&2
  exit 1
}
rg -q '^site:' "$root/secrets/secrets.example.yaml" || {
  printf 'missing private site schema section\n' >&2
  exit 1
}
for key in base_domain timezone homeassistant_zigbee_router_serial_id; do
  rg -q "^  ${key}:" "$root/secrets/secrets.example.yaml" || {
    printf 'missing private site schema key: %s\n' "$key" >&2
    exit 1
  }
done
for secret in s3_endpoint s3_region s3_bucket s3_prefix s3_access_key_id s3_secret_access_key repository_password; do
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
[[ $network_count == 12 ]] || { printf 'expected 12 networks, found %s\n' "$network_count" >&2; exit 1; }
[[ $(rg -l '^Options=isolate=true$' "$root/quadlet/networks" | wc -l | tr -d ' ') == 12 ]] || {
  printf 'every network must explicitly use bridge isolation\n' >&2
  exit 1
}
for backend in forgejo homeassistant immich searxng; do
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

for blocked_network in radicale syncthing vaultwarden; do
  rg -q '^Internal=true$' "$root/quadlet/networks/$blocked_network.network" || {
    printf 'network must block external access: %s\n' "$blocked_network" >&2
    exit 1
  }
done

if rg -l --glob '*postgres.container' --glob '*mariadb.container' \
  --glob '*valkey.container' --glob '*mosquitto.container' \
  '^Network=.*-edge\.network$' "$containers"; then
  printf 'a database, cache, or MQTT container is attached to an edge network\n' >&2
  exit 1
fi

if rg -n -i -g '!tests/static.sh' '\bredis\b' "$root"; then
  printf 'stale Redis project reference found; only vendor REDIS_* environment keys may remain\n' >&2
  exit 1
fi
rg -q '^Network=immich-ml-egress.network$' \
  "$containers/immich/immich-machine-learning.container" || {
  printf 'Immich machine learning is missing its dedicated egress network\n' >&2
  exit 1
}

rg -q '^HOMEASSISTANT_TRUSTED_PROXY_SUBNET=10\.200\.12\.0/24$' "$root/bin/render-config" || {
  printf 'Home Assistant must trust its Caddy edge subnet\n' >&2
  exit 1
}

while IFS= read -r unit; do
  base=$(basename -- "$unit")
  case "$base" in
    *-postgres.container|*-mariadb.container) ;;
    *)
      printf 'database Image= unit must be named *-postgres.container or *-mariadb.container: %s\n' \
        "$unit" >&2
      exit 1
      ;;
  esac
done < <(rg -l '^Image=.*(postgres|mariadb)' "$containers" --glob '*.container')

rg -q '^Volume=homeassistant-config.volume:/config:U$' \
  "$containers/homeassistant/homeassistant.container" || {
  printf 'Home Assistant config volume must use :U\n' >&2
  exit 1
}
if rg -q 'configuration.yaml' \
  "$containers/homeassistant/homeassistant-zigbee2mqtt.container"; then
  printf 'Zigbee2MQTT must not bind-mount configuration.yaml\n' >&2
  exit 1
fi
rg -q '^EnvironmentFile=%t/homelab/rendered/homeassistant/zigbee2mqtt.env$' \
  "$containers/homeassistant/homeassistant-zigbee2mqtt.container" || {
  printf 'Zigbee2MQTT must load the rendered ZIGBEE2MQTT_CONFIG_* env file\n' >&2
  exit 1
}
rg -q '^Secret=homeassistant-mosquitto-password,type=env,target=ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD$' \
  "$containers/homeassistant/homeassistant-zigbee2mqtt.container" || {
  printf 'Zigbee2MQTT must inject the Mosquitto password as a Podman secret\n' >&2
  exit 1
}
[[ -f $root/config/templates/homeassistant/zigbee2mqtt.env ]] || {
  printf 'missing Zigbee2MQTT env template\n' >&2
  exit 1
}
[[ ! -e $root/config/templates/homeassistant/zigbee2mqtt.yaml ]] || {
  printf 'retired Zigbee2MQTT YAML overlay must not exist\n' >&2
  exit 1
}
caddyfile="$root/config/templates/caddy/Caddyfile"
bookmarks_header=false
in_bookmarks=false
depth=0
while IFS= read -r line; do
  # shellcheck disable=SC2016
  if [[ $line == 'bookmarks.{$BASE_DOMAIN} {' ]]; then
    in_bookmarks=true
    depth=1
    continue
  fi
  if $in_bookmarks; then
    [[ $line == *'import default-header'* ]] && bookmarks_header=true
    opens=$(printf '%s' "$line" | tr -cd '{')
    closes=$(printf '%s' "$line" | tr -cd '}')
    depth=$((depth + ${#opens} - ${#closes}))
    if ((depth <= 0)); then
      break
    fi
  fi
done <"$caddyfile"
$bookmarks_header || {
  printf 'Caddy bookmarks site must import default-header\n' >&2
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

action_line_re='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}[[:space:]]+# v[0-9]+(\.[0-9]+){1,2}$'
while IFS= read -r action_line; do
  [[ $action_line =~ $action_line_re ]] || {
    printf 'GitHub Action must use a full SHA and version comment: %s\n' "$action_line" >&2
    exit 1
  }
done < <(rg --no-filename '^[[:space:]]*(-[[:space:]]+)?uses:' "$workflows")

printf 'static topology validation passed\n'
