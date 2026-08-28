# Restore onto a replacement host

This procedure migrates the complete deployment to a fresh Fedora/RHEL Linux
host on amd64 or arm64. Do not reconcile the replacement host before its
volumes have been restored.

On arm64, `bootstrap-host` installs `qemu-user-binfmt` and
`qemu-user-static-x86`, enables `systemd-binfmt`, and verifies the enabled
`qemu-x86_64` binfmt registration. Supernote's amd64-only `notelib` and
`supernote-service` images run through that emulation; all other images use
the native host architecture. If the distribution cannot provide the required
packages or registration, bootstrap and reconciliation stop before activation.

## Freeze and verify the source

As `homelab`, create a protected final snapshot and leave applications and
backup/reconciliation timers stopped:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
~/current/bin/backup --tag migration --leave-stopped-on-success
snapshot=$(<~/.local/state/homelab/last-backup-snapshot)
~/current/bin/restic snapshots "$snapshot"
printf 'Migration snapshot: %s\n' "$snapshot"
exit
```

If the command fails, it restarts the source deployment. Resolve the error and
repeat it. After success, do not start the source applications again; doing so
would create two divergent copies of the state.

On the operator workstation, check that the snapshot is readable using the
offline operator identity. Install the pinned Restic release, then point the
wrapper at its absolute path if it is not `/usr/local/bin/restic`:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt
export HOMELAB_RESTIC_BIN=/ABSOLUTE/PATH/TO/restic
./bin/restic check
./bin/restic snapshots --tag migration
```

Obtain the exact host identity for bootstrap without restoring all data to the
workstation:

```bash
umask 077
./bin/restic dump SNAPSHOT_ID \
  /home/homelab/.config/sops/age/keys.txt > /SECURE/PATH/host-age-keys.txt
age-keygen -y /SECURE/PATH/host-age-keys.txt
```

The recipient must be one of the two recipients in `.sops.yaml`.

## Bootstrap without starting applications

Create a fresh repository-scoped GitHub deploy key and verified known-hosts
file as described in the main README. Copy the trusted working tree and those
files to the replacement host, then run:

```bash
sudo ./bin/bootstrap-host \
  --repo git@github.com:OWNER/REPOSITORY.git \
  --git-key ../github-deploy-key \
  --known-hosts ../github-known-hosts \
  --host-age-key /SECURE/PATH/host-age-keys.txt \
  --firewalld-zone public
```

The printed recipient must match the one checked above. Attach the Zigbee
coordinator first; if its stable serial ID changed, update and push
`config/site.env` before bootstrap.

## Restore volumes and auxiliary state

Run the following as `homelab` before the first reconciliation:

```bash
sudo -iu homelab
set -Eeuo pipefail
umask 077
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
cd ~/git/repository
snapshot=SNAPSHOT_ID

./bin/restic dump "$snapshot" \
  /home/homelab/.local/state/homelab/backup-metadata/volume-list.txt \
  > /tmp/backup-volume-list.txt

while IFS= read -r volume_file; do
  volume=$(sed -n 's/^VolumeName=//p' "$volume_file")
  label=$(sed -n 's/^Label=//p' "$volume_file")
  grep -Fxq "$volume" /tmp/backup-volume-list.txt
  podman volume exists "$volume" && {
    printf 'Refusing existing volume: %s\n' "$volume" >&2
    exit 1
  }
  podman volume create --label "$label" "$volume" >/dev/null
  mountpoint=$(podman volume inspect --format '{{.Mountpoint}}' "$volume")
  podman unshare ./bin/restic restore "$snapshot:$mountpoint" \
    --target "$mountpoint"
done < <(find quadlet/volumes -type f -name '*.volume' | sort)

./bin/restic dump "$snapshot" \
  /home/homelab/.local/state/homelab/deployed-commit \
  > ~/.local/state/homelab/deployed-commit
chmod 0600 ~/.local/state/homelab/deployed-commit
rm -f /tmp/backup-volume-list.txt

backup_commit=$(<~/.local/state/homelab/deployed-commit)
git fetch --prune origin main
git cat-file -e "$backup_commit^{commit}"
git merge-base --is-ancestor "$backup_commit" origin/main
sops --decrypt secrets/secrets.sops.yaml >/dev/null
```

Every command must succeed. A failed ancestry check requires deploying the
matching Git revision before allowing application database migrations.

## Activate and cut over

```bash
~/git/repository/bin/reconcile
~/current/bin/status
~/current/bin/restic check
exit
```

Verify application data and logins. Check recent SELinux denials and confirm
that every restored volume has expected ownership and `container_file_t`
labels. Move wildcard DNS records and router forwards only after validation,
then verify HTTPS and Syncthing connectivity.

Remove temporary bootstrap/recovery files and the old GitHub deploy key only
after the replacement host and an independent repository check succeed. Keep
the old host powered off until the migration snapshot is no longer needed.
