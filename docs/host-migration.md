# Host migration and restore

This procedure applies to deployments managed by rootless Podman Quadlets.
It covers two primary migration workflows:

1. **External data disk migration (direct transfer)**: For hosts using an
   external storage disk (`/home/homelab/.local/share/containers/storage`)
   that moves with the host. All named volumes and container images already
   reside on the disk, so only host identity and auxiliary state are copied via
   the operator workstation.
2. **Disaster recovery restore from S3**: For hosts with empty, replaced, or
   wiped disks where all named volumes and auxiliary state are restored
   from an encrypted Restic snapshot.

This document also covers backing up and restoring the **operator workstation**.

Snapshots made by the old Docker deployment contain `/data/containers` instead;
use [the legacy-main-to-quadlets migration guide](legacy-main-to-quadlets.md)
for those snapshots. Do not pass a legacy snapshot to the volume-by-mountpoint
restore loop.

This procedure migrates the complete deployment to a fresh Fedora 44 or Fedora
45 host on amd64 or arm64. Do not reconcile the replacement host before its
volumes or external storage have been mounted and verified.

On arm64, `bootstrap-host` installs `qemu-user-binfmt` and
`qemu-user-static-x86`, enables `systemd-binfmt`, and verifies the enabled
`qemu-x86_64` binfmt registration. Native multi-architecture images use
the native host architecture. If the distribution cannot provide the required
packages or registration, bootstrap and reconciliation stop before activation.

## Freeze and verify the source

On the source host, create a protected final snapshot and leave applications and
backup/reconciliation timers stopped. This guarantees a cold, consistent
database shutdown (PostgreSQL, MariaDB, SQLite, Valkey) before the disk is
unplugged or migrated:

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

---

## Operator workstation backup and restore

The operator workstation holds the offline Age identity (`operator.txt`) required
to decrypt secrets and recover the deployment if host identities are lost.

### Backing up the operator workstation

Run on the operator workstation:

```bash
# 1. Create a secure backup destination (e.g. Syncthing, encrypted drive)
mkdir -p ~/Syncthing/homelab/operator
chmod 0700 ~/Syncthing/homelab/operator

# 2. Copy the operator age identity
cp -a ~/.config/sops/age/operator.txt ~/Syncthing/homelab/operator/

# 3. Copy any additional age configuration if present
if [[ -d ~/.config/sops/age ]]; then
  cp -a ~/.config/sops/age ~/Syncthing/homelab/operator/
fi

# 4. Verify all local repository changes are committed and pushed
cd ~/src/homelab
git status
git push origin main

# 5. Restrict permissions
chmod -R go-rwx ~/Syncthing/homelab/operator
```

### Restoring the operator workstation

On a new or reinstalled operator workstation:

```bash
# 1. Restore the operator age identity
mkdir -p ~/.config/sops/age
cp ~/Syncthing/homelab/operator/operator.txt ~/.config/sops/age/operator.txt
chmod 0700 ~/.config/sops/age
chmod 0600 ~/.config/sops/age/operator.txt

# 2. Clone the repository
git clone git@github.com:OWNER/REPOSITORY.git ~/src/homelab
cd ~/src/homelab

# 3. Test that SOPS decrypts repository secrets with the operator identity
SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt sops secrets/secrets.sops.yaml
```

---

## Workflow 1: External data disk migration (direct transfer)

Use this workflow when the external data disk
(`/home/homelab/.local/share/containers/storage`) moves to the new host.
Because all named volumes already exist on the disk, you only transfer the
host identity and auxiliary state files via the operator workstation.

### Step 1: Back up host state to the operator workstation

Run from the operator workstation (replace `10.10.0.3` and `pi` with your host IP and admin user):

```bash
mkdir -p ~/Syncthing/homelab/host
chmod 0700 ~/Syncthing/homelab/host

# Stage a temporary archive on homelab (user homelab owns files mode 0700/0600)
ssh -t pi@10.10.0.3 "sudo tar -czvf /tmp/homelab-host-backup.tar.gz \
  -C /home/homelab \
  .config/sops/age/keys.txt \
  .ssh \
  .local/state/homelab && \
  sudo chown pi:pi /tmp/homelab-host-backup.tar.gz"

# Copy the archive to the operator workstation
scp pi@10.10.0.3:/tmp/homelab-host-backup.tar.gz ~/Syncthing/homelab/host/

# Remove the temporary staging archive on the host
ssh pi@10.10.0.3 "rm -f /tmp/homelab-host-backup.tar.gz"

# Extract the archive in the backup directory
tar -xzvf ~/Syncthing/homelab/host/homelab-host-backup.tar.gz -C ~/Syncthing/homelab/host/
chmod -R go-rwx ~/Syncthing/homelab/host
```

This backs up:
- `.config/sops/age/keys.txt`: Host Age private key to decrypt secrets.
- `.ssh/id_ed25519` and `.ssh/known_hosts`: GitHub deploy key and fingerprints.
- `.local/state/homelab/deployed-commit`: Pinned Git commit matching database schemas.
- `.local/state/homelab/backup-metadata/`: Volume manifests and backup records.

### Step 2: Stage credentials on the replacement host

From the operator workstation, copy the credentials to the new host:

```bash
ssh pi@NEW_HOST "mkdir -p /home/pi/homelab-restore"
scp -r ~/Syncthing/homelab/host/* pi@NEW_HOST:/home/pi/homelab-restore/
ssh pi@NEW_HOST "chmod -R go-rwx /home/pi/homelab-restore"
```

### Step 3: Run bootstrap on the replacement host

Log into the replacement host and find the stable disk identifier:

```bash
ssh pi@NEW_HOST
ls -l /dev/disk/by-id/
```

Clone the repository and run `bootstrap-host`.

> [!CAUTION]
> **Do NOT pass `--format-data-disk`!**
> Omitting `--format-data-disk` mounts the existing XFS/ext4 partition without
> erasing existing volumes or images.

```bash
git clone git@github.com:OWNER/REPOSITORY.git ~/homelab-repo
cd ~/homelab-repo

sudo ./bin/bootstrap-host \
  --repo git@github.com:OWNER/REPOSITORY.git \
  --git-key /home/pi/homelab-restore/.ssh/id_ed25519 \
  --known-hosts /home/pi/homelab-restore/.ssh/known_hosts \
  --host-age-key /home/pi/homelab-restore/.config/sops/age/keys.txt \
  --data-disk /dev/disk/by-id/DEVICE
```

Confirm that `/home/homelab/.local/share/containers/storage` is mounted before proceeding.

### Step 4: Restore auxiliary state

Restore the deployed commit and backup metadata into the `homelab` home directory:

```bash
sudo cp -r /home/pi/homelab-restore/.local/state/homelab /home/homelab/.local/state/
sudo chown -R homelab:homelab /home/homelab/.local/state
sudo chmod 0700 /home/homelab/.local/state/homelab
```

### Step 5: Verify Git commit and reconcile

Switch to the `homelab` user to verify state and activate:

```bash
sudo -iu homelab
set -Eeuo pipefail
umask 077
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
cd ~/git/repository

backup_commit=$(<~/.local/state/homelab/deployed-commit)
git fetch --prune origin main
git cat-file -e "$backup_commit^{commit}"
git merge-base --is-ancestor "$backup_commit" origin/main
sops --decrypt secrets/secrets.sops.yaml >/dev/null

~/git/repository/bin/reconcile
~/current/bin/status
exit
```

### Step 6: Clean up staging files

Remove temporary files on the new host:

```bash
rm -rf /home/pi/homelab-restore ~/homelab-repo
```

---

## Workflow 2: Disaster recovery restore from S3 Restic snapshot

Use this workflow when restoring onto a host with an empty, formatted, or
replacement drive where volume state must be restored from S3.

### Step 1: Verify the snapshot and extract host identity

On the operator workstation, verify the snapshot with the offline operator key
and extract the host Age identity:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt
export HOMELAB_RESTIC_BIN=/ABSOLUTE/PATH/TO/restic
./bin/restic check
./bin/restic snapshots --tag migration

umask 077
./bin/restic dump SNAPSHOT_ID \
  /home/homelab/.config/sops/age/keys.txt > /SECURE/PATH/host-age-keys.txt
age-keygen -y /SECURE/PATH/host-age-keys.txt
```

The printed recipient must match one of the two recipients in `.sops.yaml`.

### Step 2: Bootstrap the replacement host

Generate a fresh deploy key and verified known-hosts file as described in
the main README. Copy them to the replacement host, then run:

```bash
sudo ./bin/bootstrap-host \
  --repo git@github.com:OWNER/REPOSITORY.git \
  --git-key ../github-deploy-key \
  --known-hosts ../github-known-hosts \
  --host-age-key /SECURE/PATH/host-age-keys.txt \
  --data-disk /dev/disk/by-id/DEVICE \
  --format-data-disk
```

Pass `--format-data-disk` to initialize the disk as XFS, or `--no-data-disk`
if Podman storage resides on the OS disk. Confirm that
`/home/homelab/.local/share/containers/storage` is mounted.

### Step 3: Restore volumes and auxiliary state

Run as `homelab` before reconciling:

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

---

## Activate and cut over

After either migration workflow finishes:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
~/git/repository/bin/reconcile
~/current/bin/status
~/current/bin/restic check
exit
```

1. Verify application data and logins.
2. Check recent SELinux denials (`sudo ausearch -m avc -ts recent` or `sudo journalctl -t setroubleshoot`).
3. Confirm that every restored volume has expected ownership and `container_file_t` labels.
4. Move wildcard DNS records and router port forwards (HTTPS 443, Syncthing 22000) to the new host IP.
5. Verify HTTPS access, websocket functionality, and Syncthing connectivity.
6. Remove temporary bootstrap and recovery files on both the operator machine and the host.
7. Keep the old host powered off until the migration has been verified in production.
