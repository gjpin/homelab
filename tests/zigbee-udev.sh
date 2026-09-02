#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/bin/lib.sh"

serial='usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_cec437d19249ef118c40d58cff00cc63-if00-port0'
[[ $(zigbee_udev_id_serial "$serial") == \
  'Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_cec437d19249ef118c40d58cff00cc63' ]] || {
  printf 'udev ID_SERIAL derivation failed for a by-id basename\n' >&2
  exit 1
}

[[ $(zigbee_udev_id_serial \
  'Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_cec437d19249ef118c40d58cff00cc63') == \
  'Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_cec437d19249ef118c40d58cff00cc63' ]] || {
  printf 'udev ID_SERIAL derivation changed a bare serial\n' >&2
  exit 1
}

rule=$("$root/bin/install-zigbee-udev" --print-rule "$serial")
[[ $rule == 'ACTION=="add|change", SUBSYSTEM=="tty", ENV{ID_SERIAL}=="Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_cec437d19249ef118c40d58cff00cc63", MODE="0660", GROUP="dialout", TAG-="uaccess"' ]] || {
  printf 'unexpected Zigbee udev rule:\n%s\n' "$rule" >&2
  exit 1
}

if "$root/bin/install-zigbee-udev" --print-rule "$serial" homelab >/dev/null && \
  ! "$root/bin/install-zigbee-udev" --print-rule "$serial" 'homelab;true' >/dev/null 2>&1; then
  :
else
  printf 'install-zigbee-udev accepted an invalid runtime user\n' >&2
  exit 1
fi
