# Restore one older volume on the existing host

This procedure replaces one named volume while leaving other volumes at their
current versions. For applications whose database and file volumes must match,
restore the related volume set from the same snapshot or use the full host
migration workflow instead. Never mix database and application state unless
the application explicitly supports it.

## Create a safety point and select the source

Create a protected current snapshot before changing anything:

```bash
sudo -iu homelab
set -Eeuo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
~/current/bin/backup --tag pre-restore
safety_snapshot=$(<~/.local/state/homelab/last-backup-snapshot)
~/current/bin/restic snapshots --tag homelab
```

Set the exact older snapshot and declared volume, then verify the snapshot
contains that volume's mountpoint:

```bash
snapshot=OLDER_SNAPSHOT_ID
volume=homelab-vaultwarden-data
[[ $volume =~ ^homelab-[a-z0-9-]+$ ]]
volume_file=$(rg -l "^VolumeName=${volume}$" ~/current/quadlet/volumes)
test "$(wc -l <<<"$volume_file")" -eq 1
app=$(sed -n 's/^Label=io.containers.systemd.application=//p' "$volume_file")
mountpoint=$(podman volume inspect --format '{{.Mountpoint}}' "$volume")
~/current/bin/restic ls "$snapshot" "$mountpoint"
printf 'Volume %s belongs to application %s\n' "$volume" "$app"
```

Stop if the application name or snapshot contents are not exactly what was
intended.

## Replace and restore the volume

Hold the same maintenance lock used by backup and reconciliation, stop both
timers, and stop the owning application:

```bash
exec 9>"$XDG_RUNTIME_DIR/homelab-operation.lock"
flock --nonblock 9
systemctl --user stop homelab-backup.timer homelab-reconcile.timer
systemctl --user stop "homelab-$app.target"
while IFS= read -r unit; do
  ! systemctl --user is-active --quiet "$unit"
done < <(jq -r --arg app "$app" '.[$app].units[]' \
  ~/current/manifests/applications.json)
```

Confirm the application containers are stopped with `podman ps`, then perform
the destructive replacement. The `pre-restore` snapshot is the rollback point
for the current data.

```bash
label=$(sed -n 's/^Label=//p' "$volume_file")
podman volume rm "$volume"
podman volume create --label "$label" "$volume" >/dev/null
mountpoint=$(podman volume inspect --format '{{.Mountpoint}}' "$volume")
podman unshare ~/current/bin/restic restore "$snapshot:$mountpoint" \
  --target "$mountpoint"
```

Inspect ownership and SELinux labels before startup:

```bash
podman unshare find "$mountpoint" -xdev -printf '%U:%G %m %p\n' | sed -n '1,10p'
ls -ldZ "$mountpoint"
systemctl --user start "homelab-$app.target"
```

Verify all units listed for the application in
`manifests/applications.json`, then exercise its login and recovered data. Once
healthy, resume automation and release the shell lock:

```bash
systemctl --user start homelab-reconcile.timer homelab-backup.timer
~/current/bin/status
exec 9>&-
exit
```

If removal, restoration, or health verification fails, keep the application
and both timers stopped. Repeat the replacement using `$safety_snapshot` to
return to the state captured immediately before this procedure; do not let
reconciliation restart an empty or partially restored volume.
