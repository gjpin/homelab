# Migrate an old `main` snapshot to Quadlets

This is the one-time recovery procedure for the Docker deployment from the
old `main` branch. That deployment backed up a single `/data/containers` tree
with Restic. The current `main` branch backs up labeled named volumes and
uses a different repository prefix, so the current `bin/restic` wrapper cannot
open the old repository.

The migration keeps the old Restic repository read-only. It first restores a
selected snapshot to a private staging directory, copies only durable file
data into newly created Quadlet volumes, and leaves cache volumes empty. The
old Forgejo and Immich PostgreSQL 17 directories are never opened by the
PostgreSQL 18 containers: `bin/restore-legacy-postgres` runs each old directory
in a temporary rootless container, creates a logical dump, and restores it into
the corresponding empty PostgreSQL 18 volume.

Do not run the application targets until both restore commands have completed.
Keep the old repository, the staging directory, and the operator recovery
materials until the new host has passed its first backup and application
verification.

## 1. Prepare the new branch and host

On the operator workstation, use a trusted checkout of the `main` branch.
Set the real values in `config/site.env` and commit them before bootstrapping:

```dotenv
BASE_DOMAIN=your-real-domain
TIMEZONE=Europe/Lisbon
HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID=your-stable-serial-id
BACKUP_S3_ENDPOINT=https://s3.REGION.backblazeb2.com
BACKUP_S3_REGION=REGION
BACKUP_S3_BUCKET=BUCKET
BACKUP_S3_PREFIX=homelab
```

Use a new prefix such as `homelab` (or a fresh dedicated prefix). Do not
initialize or write to the old Docker repository. A new Restic repository
password is recommended; keep it separately in the operator password manager.

Create a new operator age identity if one is not already backed up:

```bash
umask 077
mkdir -p ~/.config/sops/age
age-keygen -pq -o ~/.config/sops/age/operator.txt
age-keygen -y ~/.config/sops/age/operator.txt
```

Push the site configuration, then bootstrap the fresh Fedora host from this
branch. On the new ARM64 host, omit `--host-age-key`; bootstrap will generate a
new host identity. Record the printed host recipient.

```bash
sudo ./bin/bootstrap-host \
  --repo git@github.com:OWNER/REPOSITORY.git \
  --branch main \
  --git-key ../github-deploy-key \
  --known-hosts ../github-known-hosts \
  --firewalld-zone public
```

Do not run reconciliation yet. The branch intentionally has no usable
`secrets/secrets.sops.yaml` until the recovered application credentials have
been reviewed below.

## 2. Obtain and verify the legacy Restic environment

Create a local file from the old `/etc/restic/env` values. Keep it outside Git,
mode `0600`, and include only these keys:

```dotenv
AWS_ACCESS_KEY_ID=${OLD_AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${OLD_AWS_SECRET_ACCESS_KEY}
RESTIC_PASSWORD=${OLD_RESTIC_PASSWORD}
RESTIC_REPOSITORY=${OLD_RESTIC_REPOSITORY}
AWS_DEFAULT_REGION=${OLD_AWS_DEFAULT_REGION}
```

Use the old repository URL and old Restic password exactly. Do not add the new
`BACKUP_S3_PREFIX` to this URL. Copy the file to the target host securely:

```bash
sudo install -o homelab -g homelab -m 0600 \
  /SECURE/PATH/legacy-restic.env /home/homelab/legacy-restic.env
```

If the old repository was configured at the bucket root, leave the repository
URL at the bucket root. The migration tool rejects extra environment keys,
world-readable files, and shell syntax; it never sources the file.

To inspect the legacy snapshots and retrieve the full 64-character snapshot ID:

```bash
export $(grep -v '^#' /home/homelab/legacy-restic.env | xargs)
restic snapshots --json | jq -r '.[-1].id'
```

## 3. Restore the legacy file data

Run these commands as `homelab` on the new host. Use a new, empty staging path
with enough space for the restored `/data/containers` tree and the temporary
logical dumps:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
cd ~/git/repository
snapshot=FULL_64_CHARACTER_LOWERCASE_SNAPSHOT_ID
staging="$HOME/legacy-restore-$snapshot"

./bin/restore-legacy-restic \
  --snapshot "$snapshot" \
  --legacy-env "$HOME/legacy-restic.env" \
  --staging-dir "$staging" \
  --dry-run

./bin/restore-legacy-restic \
  --snapshot "$snapshot" \
  --legacy-env "$HOME/legacy-restic.env" \
  --staging-dir "$staging"
```

The first command verifies the inputs without changing volumes. The real run
performs `restic snapshots`, `restic check`, and a read-only restore, then
creates every active Quadlet volume with its declared workload label. It copies
the durable mappings below, normalizes Forgejo's layout for rootless execution,
and leaves caches, generated configuration, and both PostgreSQL volumes empty:

| Legacy path below `/data/containers` | Quadlet volume |
| --- | --- |
| `caddy/volumes/caddy` | `homelab-caddy-data` |
| `caddy/volumes/bookmarks` | `homelab-caddy-bookmarks` |
| `forgejo/volumes/data` | `homelab-forgejo-data` |
| `homeassistant/volumes/homeassistant` | `homelab-homeassistant-config` |
| `homeassistant/volumes/mosquitto/data` | `homelab-homeassistant-mosquitto-data` |
| `homeassistant/volumes/zigbee2mqtt` | `homelab-homeassistant-zigbee2mqtt` |
| `immich/volumes/immich` | `homelab-immich-data` |
| `radicale/volumes/radicale` | `homelab-radicale-collections` |
| `supernote/volumes/mariadb` | `homelab-supernote-mariadb` |
| `supernote/volumes/supernote/data`, `recycle`, `logs-*`, `convert` | corresponding `homelab-supernote-*` volumes |
| `syncthing/volumes/syncthing` | `homelab-syncthing-data` |
| `vaultwarden/volumes/vaultwarden` | `homelab-vaultwarden-data` |

AnythingLLM and Docs MCP are intentionally not restored or activated because
they remain inactive incubator bundles on the `main` branch.

## 4. Convert PostgreSQL 17 data

The repository contains the exact, digest-pinned PostgreSQL 17 migration image
metadata in `config/legacy-migration.env`. The command below requires the
legacy generated PostgreSQL configs and data directories in the staging tree.
It creates no application network and uses temporary containers running as
unprivileged `postgres` with no capabilities, no network, a read-only root,
and a 1024-process limit.

```bash
./bin/restore-legacy-postgres \
  --staging-dir "$staging" \
  --dry-run

./bin/restore-legacy-postgres \
  --staging-dir "$staging"
```

The logical dumps are retained at
`$staging/quadlet-postgres-dumps/`. Temporary containers, temporary volumes,
and runtime environment files are removed after success or failure. The
target PostgreSQL volumes are never removed automatically. If a migration
fails, inspect the retained staging tree and rerun only after resolving the
cause; use a new empty target host/volume set rather than mixing partial
database state.

## 5. Create the encrypted deployment secrets

The restored staging tree now contains the old generated configuration. On the
operator workstation, create the encrypted secrets using the host recipient
printed by `bootstrap-host` and the operator recipient. Run this against the
operator checkout, not through the host's read-only deploy key:

```bash
./bin/init-secrets \
  --host-recipient age1pq1HOST_RECIPIENT \
  --operator-recipient age1pq1OPERATOR_RECIPIENT
```

The command generates several new passwords. Before committing the encrypted
file, edit it with SOPS and replace values that must remain compatible with
restored application state. Read the values from the staging tree in a
protected terminal or editor; never put a recovered secret in a command
argument or plaintext Git file:

- `forgejo.database_password` must be the password in
  `$staging/data/containers/forgejo/docker/config.env`.
- `immich.database_password` must be the password in
  `$staging/data/containers/immich/docker/config.env`.
- `homeassistant.mosquitto_password` must be the password in the restored
  Zigbee2MQTT configuration.
- `supernote.database_root_password` and
  `supernote.database_user_password` must match the restored Supernote
  `supernote/docker/config.env`.

The Caddy bookmarks bcrypt record, Radicale htpasswd record, and SearXNG
secret key can likewise be preserved from the restored legacy configuration if
desired. Alternatively, use the newly generated credentials and record them.
The new Vaultwarden admin secret is an Argon2 hash; choose and record a new
admin password unless you deliberately convert the old plaintext token with
the host's `argon2` utility. Never commit a plaintext recovered credential.

Commit and push `.sops.yaml` and `secrets/secrets.sops.yaml`. Then update the
target checkout, still without reconciling:

```bash
sudo -iu homelab
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
cd ~/git/repository
git pull --ff-only origin main
```

## 6. Reconcile and verify

Run reconciliation and audit:

```bash
./bin/reconcile
./bin/status
./bin/security-audit
```

Before reconciliation, review any deployment-owned files that the current
branch mounts read-only over restored files. In particular:
- `config/templates/homeassistant/automations.yaml` is currently `[]`; merge
  any desired legacy automations into that tracked template and push the change
  before activating Home Assistant.
- If you configured custom device names or settings in legacy Zigbee2MQTT
  (`zigbee2mqtt/configuration.yaml`), note that the Quadlet unit mounts
  `config/templates/homeassistant/zigbee2mqtt.yaml` read-only. Merge required
  device or group blocks into that template prior to activation.
- `bin/restore-legacy-restic` automatically adapts legacy Forgejo layout
  to `/var/lib/gitea/custom/conf/app.ini` and rewrites internal `/data/` paths.
- The current Caddy, Radicale, SearXNG, Mosquitto, Zigbee2MQTT, and Supernote
  configuration templates are the authoritative deployment configuration;
  restored volume data remains the application state.

After the deployment is healthy, initialize the new repository exactly once
using the configured prefix and the repository password stored in SOPS:

```bash
./bin/restic init
./bin/restic cat config
systemctl --user start homelab-backup.service
./bin/restic snapshots --latest 1
./bin/status
```

Do not run `init` against the old repository. Confirm the first new snapshot,
the host age identity, and the expected named-volume inventory before removing
the legacy environment file or staging directory. Keep the old B2 repository
untouched until application logins, Forgejo/Immich databases, Supernote data,
Home Assistant, and Syncthing have all been checked.
