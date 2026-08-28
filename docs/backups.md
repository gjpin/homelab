# Encrypted S3 volume backups

Restic creates encrypted, deduplicated snapshots in an S3-compatible object
store. The first snapshot uploads all selected data. Later snapshots scan the
same paths but upload only new chunks; every snapshot is still independently
restorable as a complete point in time.

Backups are cold: all application targets are stopped for the scan and upload
so PostgreSQL, MariaDB, SQLite, Valkey, Redis, and ordinary files share one consistent
point in time. The initial upload can therefore cause substantial downtime.

## Configure the repository

Create a private bucket and a bucket-scoped application key with list, read,
write, and delete access. For Backblaze B2, use the bucket's S3 endpoint, not
the native B2 API endpoint or a master key. Configure the bucket lifecycle to
keep only the latest version of each object; otherwise objects deleted by
restic pruning remain as chargeable hidden B2 versions.

Set these non-secret values in `config/site.env`:

```dotenv
BACKUP_S3_ENDPOINT=https://s3.REGION.backblazeb2.com
BACKUP_S3_REGION=REGION
BACKUP_S3_BUCKET=BUCKET
BACKUP_S3_PREFIX=homelab
```

`BACKUP_S3_ENDPOINT` must be an HTTPS origin without a trailing slash. Keep the
prefix stable across host migrations.

Fresh installations collect all three backup secrets through
`bin/init-secrets`. For an existing encrypted secrets file, edit it on the
operator workstation:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt \
  sops secrets/secrets.sops.yaml
```

Add:

```yaml
backup:
  s3_access_key_id: BACKUP_KEY_ID
  s3_secret_access_key: BACKUP_APPLICATION_KEY
  repository_password: LONG_UNIQUE_RESTIC_PASSWORD
```

Store the repository password in the operator password manager. It is also
encrypted in Git for unattended operation, but losing both age identities and
the separately recorded password makes the repository unrecoverable.

Commit and push the configuration and encrypted secret changes, reconcile the
host, then install the pinned restic binary on a host upgraded from an older
revision:

```bash
sudo dnf install -y bzip2
sudo /home/homelab/current/bin/install-restic
```

Fresh hosts install restic during `bootstrap-host`.

Confirm that the host timezone matches `TIMEZONE` in `config/site.env`; on an
older host, correct it before enabling the timer:

```bash
timedatectl
sudo timedatectl set-timezone Europe/Lisbon
```

Initialize the repository exactly once as `homelab`. The scheduled job never
initializes a missing repository automatically:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
~/current/bin/restic init
~/current/bin/restic cat config
exit
```

## Automatic and manual backups

The enabled `homelab-backup.timer` runs at 03:00 in the host timezone, with up
to ten minutes of randomized delay. A missed run is started after the host
comes back online. Automatic snapshots retain 2 daily, 4 weekly, and 2 monthly
points; restic deduplication shares unchanged chunks between them.

Trigger the same retained backup manually and wait for completion:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user start homelab-backup.service
~/current/bin/status
journalctl --user -u homelab-backup.service --since today
exit
```

Create a protected snapshot that automatic retention will not remove:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
~/current/bin/backup --tag manual
~/current/bin/restic snapshots --tag manual
exit
```

Protected `manual`, `pre-restore`, and `migration` snapshots must be removed
deliberately when no longer needed:

```bash
~/current/bin/restic forget SNAPSHOT_ID --prune
~/current/bin/restic check
```

Do not continue after a failed backup until `bin/status` confirms that the
applications and both timers are active. The backup script attempts that
restart on every failure and records successful snapshot IDs under
`~/.local/state/homelab`. If restic reports a partial snapshot, the script
forgets it immediately; a failed cleanup is recorded locally, shown by
`bin/status`, and retried before the next run stops any application.

## What is backed up

- Every named volume declared by `quadlet/volumes`, after verifying it exactly
  matches the labeled inventory for active applications.
- The deployed Git commit, host age identity, and a volume-to-mountpoint
  manifest.

The private Git repository, operator age identity, and plaintext repository
password remain independent recovery prerequisites. Releases, images,
rendered configuration, caches outside named volumes, and host firewall units
are recreated rather than backed up.

Volumes belonging to inactive incubator bundles are intentionally outside this
backup inventory.
