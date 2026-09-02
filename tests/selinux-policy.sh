#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
shopt -s nullglob
modules=("$root"/selinux/*.te)
((${#modules[@]} > 0)) || { printf 'missing SELinux policy sources under selinux/\n' >&2; exit 1; }

rg -q '^module homelab_caddy_https_proxy 1\.0;$' "$root/selinux/caddy-https-proxy.te" || {
  printf 'SELinux policy module name is not homelab_caddy_https_proxy 1.0\n' >&2
  exit 1
}
rg -q 'type systemd_socket_proxyd_t;' "$root/selinux/caddy-https-proxy.te" || {
  printf 'SELinux policy does not mention systemd_socket_proxyd_t\n' >&2
  exit 1
}
rg -q 'type http_port_t;' "$root/selinux/caddy-https-proxy.te" || {
  printf 'SELinux policy does not mention http_port_t\n' >&2
  exit 1
}
rg -q '^module homelab_zigbee2mqtt_network 1\.0;$' "$root/selinux/zigbee2mqtt-network.te" || {
  printf 'SELinux policy module name is not homelab_zigbee2mqtt_network 1.0\n' >&2
  exit 1
}
rg -q 'typeattribute container_device_t container_net_domain;' \
  "$root/selinux/zigbee2mqtt-network.te" || {
  printf 'Zigbee2MQTT SELinux policy does not grant container_net_domain\n' >&2
  exit 1
}
rg -q '^module homelab_homeassistant_dbus 1\.0;$' "$root/selinux/homeassistant-dbus.te" || {
  printf 'SELinux policy module name is not homelab_homeassistant_dbus 1.0\n' >&2
  exit 1
}
rg -q 'allow container_t system_dbusd_var_run_t:sock_file write;' \
  "$root/selinux/homeassistant-dbus.te" || {
  printf 'Home Assistant D-Bus SELinux policy does not allow socket write\n' >&2
  exit 1
}
rg -q 'allow container_t system_dbusd_t:unix_stream_socket connectto;' \
  "$root/selinux/homeassistant-dbus.te" || {
  printf 'Home Assistant D-Bus SELinux policy does not allow connectto\n' >&2
  exit 1
}

if ! command -v checkmodule >/dev/null 2>&1; then
  printf 'checkmodule unavailable; skipped policy compile\n' >&2
  exit 0
fi

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
for te in "${modules[@]}"; do
  module=$(awk '/^module[[:space:]]/{print $2; exit}' "$te")
  checkmodule -M -m -o "$workdir/$module.mod" "$te"
  if command -v semodule_package >/dev/null 2>&1; then
    semodule_package -o "$workdir/$module.pp" -m "$workdir/$module.mod"
  fi
done
