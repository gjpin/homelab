# Backup and restore runbook

## Operator

### Backup

1. Define paths and create the destination with restricted permissions.

```bash
OPERATOR_REPO="$HOME/src/homelab"
OPERATOR_BACKUP="$HOME/Syncthing/homelab/operator"
OPERATOR_AGE_KEY="$HOME/.config/sops/age/operator.txt"

install -d -m 0700 "$OPERATOR_BACKUP"
```

2. Verify the local Git repository is clean and matches `origin/main`.

```bash
cd "$OPERATOR_REPO"

git fetch --prune origin main

test -z "$(git status --porcelain)" || {
  echo 'Repository has uncommitted changes' >&2
  exit 1
}

test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
  echo 'Repository does not match origin/main' >&2
  exit 1
}
```

3. Copy the operator Age identity.

```bash
test -r "$OPERATOR_AGE_KEY"

install -m 0600 \
  "$OPERATOR_AGE_KEY" \
  "$OPERATOR_BACKUP/operator.txt"

age-keygen -y "$OPERATOR_BACKUP/operator.txt" \
  >"$OPERATOR_BACKUP/operator-recipient.txt"

chmod 0600 "$OPERATOR_BACKUP/operator-recipient.txt"
```

4. Create an independent backup of the complete Git repository.

```bash
git bundle create \
  "$OPERATOR_BACKUP/homelab.git.bundle" \
  --all

git bundle verify \
  "$OPERATOR_BACKUP/homelab.git.bundle"
```

5. Copy the critical encrypted configuration separately.

```bash
install -m 0600 \
  .sops.yaml \
  "$OPERATOR_BACKUP/sops-config.yaml"

install -m 0600 \
  secrets/secrets.sops.yaml \
  "$OPERATOR_BACKUP/secrets.sops.yaml"
```

6. Verify that the backed-up identity decrypts the backed-up secrets.

```bash
SOPS_AGE_KEY_FILE="$OPERATOR_BACKUP/operator.txt" \
  sops \
    --config "$OPERATOR_BACKUP/sops-config.yaml" \
    --decrypt \
    --input-type yaml \
    --output-type json \
    "$OPERATOR_BACKUP/secrets.sops.yaml" \
  >/dev/null &&
  echo 'Operator identity successfully decrypts deployment secrets'
```

7. Verify that the Forgejo Runner registration is present.

```bash
SOPS_AGE_KEY_FILE="$OPERATOR_BACKUP/operator.txt" \
  sops \
    --config "$OPERATOR_BACKUP/sops-config.yaml" \
    --decrypt \
    --input-type yaml \
    --output-type json \
    "$OPERATOR_BACKUP/secrets.sops.yaml" |
  jq -e '
    (.forgejo.runner_secret | test("^[0-9a-f]{40}$")) and
    (.forgejo.runner_uuid | test(
      "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    ))
  ' >/dev/null &&
  echo 'Forgejo Runner registration is present'
```

8. Generate and verify checksums.

```bash
cd "$OPERATOR_BACKUP"

find . \
  -type f \
  ! -name SHA256SUMS \
  -print |
  LC_ALL=C sort |
  while IFS= read -r backup_file; do
    sha256sum "$backup_file"
  done >SHA256SUMS

chmod 0600 SHA256SUMS
sha256sum --check SHA256SUMS
```

9. Ensure all backed-up files remain private.

```bash
chmod -R go-rwx "$OPERATOR_BACKUP"
```

### Restore

1. Define the backup location.

```bash
OPERATOR_BACKUP="$HOME/Syncthing/homelab/operator"
```

2. Verify backup checksums.

```bash
cd "$OPERATOR_BACKUP"
sha256sum --check SHA256SUMS
```

3. Restore the operator Age identity.

```bash
install -d -m 0700 "$HOME/.config/sops/age"

install -m 0600 \
  "$OPERATOR_BACKUP/operator.txt" \
  "$HOME/.config/sops/age/operator.txt"
```

4. Restore the repository from GitHub.

```bash
git clone \
  git@github.com:gjpin/homelab.git \
  "$HOME/src/homelab"

cd "$HOME/src/homelab"
```

If GitHub is unavailable, use the Git bundle instead:

```bash
git clone \
  "$OPERATOR_BACKUP/homelab.git.bundle" \
  "$HOME/src/homelab"

cd "$HOME/src/homelab"

git remote set-url origin \
  git@github.com:gjpin/homelab.git
```

5. Verify the restored operator identity.

```bash
SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/operator.txt" \
  sops \
    --config .sops.yaml \
    --decrypt \
    --output-type json \
    secrets/secrets.sops.yaml \
  >/dev/null &&
  echo 'Operator restore is valid'
```

6. Verify the Forgejo Runner registration.

```bash
SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/operator.txt" \
  sops \
    --config .sops.yaml \
    --decrypt \
    --output-type json \
    secrets/secrets.sops.yaml |
  jq -e '
    (.forgejo.runner_secret | test("^[0-9a-f]{40}$")) and
    (.forgejo.runner_uuid | test(
      "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    ))
  ' >/dev/null &&
  echo 'Forgejo Runner registration is valid'
```

## Homelab

### Backup

1. Define the destination and create it with restricted permissions.

```bash
HOST_BACKUP="$HOME/Syncthing/homelab/host"
HOST_SSH=pi@10.10.0.3

install -d -m 0700 "$HOST_BACKUP"
```

2. Create a protected Backblaze snapshot containing the current Forgejo
   database state, including the Forgejo Runner registration.

```bash
ssh -t "$HOST_SSH" '
  cd /

  HOMELAB_UID=$(id -u homelab)

  sudo runuser -u homelab -- \
    env HOME=/home/homelab \
        XDG_RUNTIME_DIR="/run/user/$HOMELAB_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$HOMELAB_UID/bus" \
    /home/homelab/current/bin/backup --tag manual
'
```

3. Package critical non-volume host state in a private staging directory.

```bash
ssh -t "$HOST_SSH" '
  set -Eeuo pipefail
  umask 077

  install -d -m 0700 /home/pi/homelab-backup-stage

  sudo tar -czf \
    /home/pi/homelab-backup-stage/homelab-host-state.tar.gz \
    -C /home/homelab \
    .config/sops/age/keys.txt \
    .ssh \
    .local/state/homelab

  sudo chown pi:pi \
    /home/pi/homelab-backup-stage/homelab-host-state.tar.gz

  chmod 0600 \
    /home/pi/homelab-backup-stage/homelab-host-state.tar.gz
'
```

4. Copy the archive to the operator backup directory.

```bash
scp \
  "$HOST_SSH:/home/pi/homelab-backup-stage/homelab-host-state.tar.gz" \
  "$HOST_BACKUP/"
```

5. Remove the temporary host copy.

```bash
ssh "$HOST_SSH" \
  'rm -f /home/pi/homelab-backup-stage/homelab-host-state.tar.gz &&
   rmdir /home/pi/homelab-backup-stage'
```

6. Verify that all required entries are present without extracting them.

```bash
for required_path in \
  .config/sops/age/keys.txt \
  .ssh/id_ed25519 \
  .ssh/known_hosts \
  .local/state/homelab/deployed-commit
do
  tar -tzf "$HOST_BACKUP/homelab-host-state.tar.gz" |
    grep -Fxq "$required_path" || {
      printf 'Missing host backup entry: %s\n' "$required_path" >&2
      exit 1
    }
done

echo 'Required host state is present'
```

7. Verify the backed-up host Age identity.

```bash
HOST_KEY_TMP=$(mktemp)

tar -xOzf \
  "$HOST_BACKUP/homelab-host-state.tar.gz" \
  .config/sops/age/keys.txt \
  >"$HOST_KEY_TMP"

chmod 0600 "$HOST_KEY_TMP"

HOST_RECIPIENT=$(age-keygen -y "$HOST_KEY_TMP")
printf 'Backed-up host recipient: %s\n' "$HOST_RECIPIENT"

grep -Fq \
  "$HOST_RECIPIENT" \
  "$HOME/src/homelab/.sops.yaml"

SOPS_AGE_KEY_FILE="$HOST_KEY_TMP" \
  sops \
    --config "$HOME/src/homelab/.sops.yaml" \
    --decrypt \
    "$HOME/src/homelab/secrets/secrets.sops.yaml" \
  >/dev/null &&
  echo 'Backed-up host identity decrypts deployment secrets'

rm -f "$HOST_KEY_TMP"
unset HOST_KEY_TMP HOST_RECIPIENT
```

8. Generate and verify an archive checksum.

```bash
cd "$HOST_BACKUP"

sha256sum homelab-host-state.tar.gz \
  >homelab-host-state.tar.gz.sha256

chmod 0600 homelab-host-state.tar.gz.sha256

sha256sum --check \
  homelab-host-state.tar.gz.sha256
```

9. Ensure the backup remains private.

```bash
chmod -R go-rwx "$HOST_BACKUP"
```

### Restore

1. Set the replacement-host address and backup paths.

```bash
NEW_HOST='pi@NEW_HOST'
HOST_BACKUP="$HOME/Syncthing/homelab/host"
OPERATOR_REPO="$HOME/src/homelab"
```

2. Verify the host archive before transferring it.

```bash
cd "$HOST_BACKUP"

sha256sum --check \
  homelab-host-state.tar.gz.sha256
```

3. Create a private staging directory on the replacement host.

```bash
ssh "$NEW_HOST" \
  'install -d -m 0700 /home/pi/homelab-restore'
```

4. Copy the archive itself. Do not use `*`, because it omits hidden paths.

```bash
scp \
  "$HOST_BACKUP/homelab-host-state.tar.gz" \
  "$NEW_HOST:/home/pi/homelab-restore/"
```

5. Extract the archive securely on the replacement host.

```bash
ssh "$NEW_HOST" '
  set -Eeuo pipefail
  umask 077

  tar -xzf \
    /home/pi/homelab-restore/homelab-host-state.tar.gz \
    -C /home/pi/homelab-restore

  chmod -R go-rwx /home/pi/homelab-restore

  test -r /home/pi/homelab-restore/.config/sops/age/keys.txt
  test -r /home/pi/homelab-restore/.ssh/id_ed25519
  test -r /home/pi/homelab-restore/.ssh/known_hosts
  test -r /home/pi/homelab-restore/.local/state/homelab/deployed-commit
'
```

6. Copy the trusted repository source to the replacement host.

```bash
ssh "$NEW_HOST" \
  'install -d -m 0700 /home/pi/podman-bootstrap/source'

rsync -a --delete --exclude .git \
  "$OPERATOR_REPO/" \
  "$NEW_HOST:/home/pi/podman-bootstrap/source/"
```

7. Run bootstrap with the restored credentials while keeping the Forgejo
   Runner disabled during restoration.

```bash
ssh -t "$NEW_HOST" '
  cd /

  sudo /home/pi/podman-bootstrap/source/bin/bootstrap-host \
    --repo git@github.com:gjpin/homelab.git \
    --git-key /home/pi/homelab-restore/.ssh/id_ed25519 \
    --known-hosts /home/pi/homelab-restore/.ssh/known_hosts \
    --host-age-key /home/pi/homelab-restore/.config/sops/age/keys.txt \
    --no-data-disk \
    --defer-forgejo-runner
'
```

If production Podman storage uses an external disk, replace `--no-data-disk`
with:

```bash
--data-disk /dev/disk/by-id/DEVICE
```

Do not use `--format-data-disk` for an existing storage filesystem.

8. Restore the non-volume deployment state.

```bash
ssh -t "$NEW_HOST" '
  set -Eeuo pipefail

  sudo install -d \
    -m 0700 \
    -o homelab \
    -g homelab \
    /home/homelab/.local/state/homelab

  sudo cp -a \
    /home/pi/homelab-restore/.local/state/homelab/. \
    /home/homelab/.local/state/homelab/

  sudo chown -R homelab:homelab \
    /home/homelab/.local/state/homelab

  sudo chmod 0700 \
    /home/homelab/.local/state/homelab
'
```

9. Restore the Backblaze volume snapshot by following
   `docs/host-migration.md`. Do not reconcile before volumes are restored.

10. At final cutover, update DNS and router forwarding, then rerun the same
    bootstrap command without `--defer-forgejo-runner`.

    If the disk was formatted during the earlier restore, do not pass
    `--format-data-disk` again.

11. Reconcile and verify after the final non-deferred bootstrap.

```bash
ssh -t "$NEW_HOST" '
  cd /

  HOMELAB_UID=$(id -u homelab)

  sudo runuser -u homelab -- \
    env HOME=/home/homelab \
        XDG_RUNTIME_DIR="/run/user/$HOMELAB_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$HOMELAB_UID/bus" \
    /home/homelab/git/repository/bin/reconcile

  sudo runuser -u homelab -- \
    env HOME=/home/homelab \
        XDG_RUNTIME_DIR="/run/user/$HOMELAB_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$HOMELAB_UID/bus" \
    /home/homelab/current/bin/status

  sudo runuser -u homelab -- \
    env HOME=/home/homelab \
        XDG_RUNTIME_DIR="/run/user/$HOMELAB_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$HOMELAB_UID/bus" \
    /home/homelab/current/bin/security-audit
'
```

Do not back up or restore these disposable/generated paths:

```text
/home/forgejo-runner
/var/lib/homelab/forgejo-runner-storage.xfs
/home/homelab/releases
/home/homelab/current
/run/user/*
```

Also keep a separate backup of your password manager. Ensure every Syncthing
peer storing these unencrypted Age and SSH private keys uses trusted, encrypted
storage.
