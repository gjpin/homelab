# Rootless Podman homelab

The deployment uses rootless Podman Quadlets, systemd user services, SOPS with
hybrid post-quantum age keys, separated edge and internal backend networks,
and a root-owned socket proxy that forwards TCP 443 to rootless Caddy on
`127.0.0.1:8443`.

## Services

| Name | URL | Description | Access to internet |
| --- | --- | --- | --- |
| [Caddy](https://github.com/caddyserver/caddy) | bookmarks.${BASE_DOMAIN} | Authenticated bookmarks and WebDAV service | Yes |
| [Forgejo](https://codeberg.org/forgejo/forgejo) | git.${BASE_DOMAIN} | Git server / DevOps platform | Yes |
| [Home Assistant](https://github.com/home-assistant/core) | home.${BASE_DOMAIN} | Home automation | Yes |
| [Zigbee2MQTT](https://github.com/Koenkk/zigbee2mqtt) | home-zigbee.${BASE_DOMAIN} | Zigbee to MQTT bridge | Yes |
| [Immich](https://github.com/immich-app/immich) | photos.${BASE_DOMAIN} | Photo and video backup solution | Yes |
| [Radicale](https://github.com/Kozea/Radicale) | contacts.${BASE_DOMAIN} | CardDAV (contact) server | No |
| [SearXNG](https://github.com/searxng/searxng) | search.${BASE_DOMAIN} | Internet metasearch engine | Yes |
| [Syncthing](https://github.com/syncthing/syncthing) | syncthing.${BASE_DOMAIN} | Continuous file synchronization | No |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | vault.${BASE_DOMAIN} | Unofficial Bitwarden-compatible server | No |

The table lists user-facing services. Supporting databases, caches, MQTT, and
worker containers stay on internal or dedicated backend networks and are not
directly exposed. “Yes” means the service has Internet egress; “No” means all
of its attached Podman networks are internal. Inbound public access is still
limited to the Caddy HTTPS proxy, plus Syncthing's documented TCP/UDP 22000
protocol ports.

## Security model

- All containers run under the dedicated, password-locked `homelab` account.
- The Git reconciler has no sudo access and cannot modify host system units.
- Only TCP 443 and Syncthing TCP/UDP 22000 are exposed externally.
- Application networks use strictly isolated deterministic `/24` ranges within
  `10.200.0.0/16`. Caddy joins edge networks only; database, cache, and MQTT
  networks are internal. Radicale, Syncthing, and Vaultwarden have
  no Internet egress; their application networks are internal while remaining
  reachable from Caddy or, for Syncthing, through its published protocol
  ports.
- Writable application state lives in rootless Podman named volumes.
- Deployment secrets are encrypted in Git and selectively imported as Podman
  secrets. Rendered secret-bearing configuration exists only below the
  homelab user's runtime directory.
- Every image root filesystem is read-only, every container drops Podman's
  default capability set, and narrowly reviewed startup exceptions are
  allowlisted. PID cgroups limit each container to 1024 processes.
- Rootless/non-root image users are selected explicitly wherever the upstream
  image supports them; documented exceptions and the required data-volume
  considerations are listed in [the rootless image policy](docs/rootless-images.md).
- CI workloads for Forgejo Actions execute under a dedicated, password-locked
  `forgejo-runner` account with separate subordinate UID/GID mappings
  (`200000-265535`), independent rootless Podman storage, host nftables egress
  isolation blocking internal RFC1918 networks, and strictly no access to
  production containers, sockets, secrets, or storage.
- SELinux must remain enforcing. Normal containers use `container_t` with
  per-container MCS separation. Only Zigbee2MQTT uses `container_device_t`, and
  the global `container_use_devices` boolean remains off. A host module adds
  `container_net_domain` to that type so Zigbee2MQTT can resolve MQTT. The host
  HTTPS socket proxy installs a targeted module so `systemd-socket-proxyd` can
  bind `http_port_t` (TCP 443) and connect to rootless Caddy on
  `127.0.0.1:8443`.
- Deployment-owned static bind mounts are read-only and privately relabeled.
- Images use explicit versions and digest pins. Renovate is configured to open
  reviewed version-and-digest updates without automerge.

The systemd socket proxy is TCP-only and hides the original peer address from
Caddy. HTTP/3 is intentionally disabled.

Podman's default seccomp profile, masked kernel paths, `nodev`/`nosuid` volume
defaults, and `no-new-privileges` remain enabled. The deployment refuses to
start if SELinux is disabled or permissive, or if global container device
access is enabled.

## Prerequisites

- Fedora 44 or Fedora 45 Linux host on amd64 or arm64 with cgroup v2 and
  SELinux enforcing. `bin/bootstrap-host` installs this host package baseline:
  `age` (at least 1.3.0), `restic` (at least 0.19.1), `ca-certificates`,
  `checkpolicy`, `container-selinux`, `curl`, `diffutils`, `firewalld`, `fuse-overlayfs`,
  `gettext-envsubst`, `gawk`, `git`, `iproute`, `jq`, `libselinux-utils`,
  `nftables`, `openssh-clients`, `passt`, `podman`, `policycoreutils`, `python3`,
  `ripgrep`, `shadow-utils`, `systemd`, `tar`, `util-linux`, and `xfsprogs`.
  The script also provisions valid `homelab` and `forgejo-runner` subordinate-ID
  ranges and installs the SOPS RPM and Forgejo Runner binary selected by the
  checksum-pinned metadata in `config/host-tools.env`.
- On arm64, bootstrap installs Fedora's `qemu-user-binfmt` and
  `qemu-user-static-x86` packages and enables `systemd-binfmt`. Native
  multi-architecture images follow the host. Bootstrap fails if the
  distribution cannot provide the required emulation packages or registration.
- Operator workstation with Bash 4 or later, Git, OpenSSH client tools,
  `rsync`, `jq`, `ripgrep`, GNU `sha256sum`, age 1.3.0 or later, a SOPS release
  with built-in age 1.3 support (3.12.0 or later), `openssl`, `argon2`, Python
  3, and its `bcrypt` module. ShellCheck is optional locally and required by
  the validation workflow. The pinned Restic release is also required on the
  workstation when performing repository recovery there.
- Administrator SSH access with sudo on the target host.
- A Cloudflare-managed DNS zone for `BASE_DOMAIN` and permission to create a
  zone-scoped API token and DNS records.
- No existing listener on TCP 443.
- `10.200.0.0/16` must not overlap a host, LAN, VPN, or container route.
- A private GitHub repository dedicated to this directory. The target host
  uses a repository-scoped, read-only SSH deploy key.
- A private S3-compatible bucket and a bucket-scoped key with list, read,
  write, and delete access. Backblaze B2 is configured through its S3 API as
  described in [the backup guide](docs/backups.md).
- The Zigbee coordinator must have a stable `/dev/serial/by-id/...` name.

## Initial installation

Perform these steps in order. Replace every uppercase placeholder.

1. In GitHub, select **New repository**, select the owner, enter the repository
   name, select **Private**, leave all initialization options cleared, and
   create the repository.

2. On the operator workstation, make this `podman` directory the repository
   root, validate it, and push the initial commit:

   ```bash
   cd /PATH/TO/homelab/podman
   git init -b main
   ./bin/validate
   ./tests/static.sh
   git add .
   git commit -m 'Initialize Podman homelab'
   git remote add origin git@github.com:OWNER/REPOSITORY.git
   git push -u origin main
   ```

   Do not put site identity in Git plaintext. `bin/init-secrets` encrypts the
   domain, timezone, Zigbee serial ID, and all `BACKUP_S3_*` values later.
   The GitHub repository is required on every replacement host; no separate
   repository backup is required if GitHub remains available and contains
   every committed change.

3. On the operator workstation, generate one unencrypted SSH deploy key for
   this host. The systemd timer cannot use a passphrase-protected key:

   ```bash
   install -d -m 0700 /SECURE/PATH/homelab-bootstrap
   ssh-keygen -t ed25519 \
     -C 'homelab HOSTNAME read-only deploy key' \
     -N '' \
     -f /SECURE/PATH/homelab-bootstrap/github-deploy-key
   ```

4. In the private GitHub repository, open **Settings** > **Deploy keys** >
   **Add deploy key**. Set the title to `homelab HOSTNAME`, paste the complete
   contents of `github-deploy-key.pub`, leave **Allow write access** cleared,
   and select **Add key**. A deploy key grants access only to this repository.

5. On the operator workstation, collect GitHub's ED25519 host key and verify
   its fingerprint against GitHub's current, independently loaded
   [published SSH fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints):

   ```bash
   ssh-keyscan -t ed25519 github.com \
     > /SECURE/PATH/homelab-bootstrap/github-known-hosts
   ssh-keygen -lf /SECURE/PATH/homelab-bootstrap/github-known-hosts
   ```

   Stop if the fingerprint does not exactly match GitHub's documentation. Do
   not accept an unverified first-use prompt. Test repository access:

   ```bash
   GIT_SSH_COMMAND='ssh -i /SECURE/PATH/homelab-bootstrap/github-deploy-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/SECURE/PATH/homelab-bootstrap/github-known-hosts' \
     git ls-remote git@github.com:OWNER/REPOSITORY.git refs/heads/main
   ```

   The command must print the `main` commit. `github-known-hosts` is required
   on a replacement host but can be recreated and reverified; it is not a
   secret and does not require backup.

6. Copy a trusted working tree and the bootstrap inputs to the target host.
   Run these commands from the `podman` repository root on the operator
   workstation:

   ```bash
   ssh ADMIN@HOST 'install -d -m 0700 ~/podman-bootstrap/source'
   rsync -a --exclude .git ./ ADMIN@HOST:podman-bootstrap/source/
   scp /SECURE/PATH/homelab-bootstrap/github-deploy-key \
     /SECURE/PATH/homelab-bootstrap/github-known-hosts \
     ADMIN@HOST:podman-bootstrap/
   ssh ADMIN@HOST 'chmod 0600 ~/podman-bootstrap/github-*'
   ```

7. Log in to the target host and run bootstrap from that trusted working tree:

   ```bash
   cd ~/podman-bootstrap/source
   sudo ./bin/bootstrap-host \
     --repo git@github.com:OWNER/REPOSITORY.git \
     --git-key ../github-deploy-key \
     --known-hosts ../github-known-hosts

   /usr/bin/restic version
   /usr/bin/age --version
   /usr/bin/sops --version --disable-version-check
   ```

   On a TTY, bootstrap asks whether Podman images and named volumes should live
   on an external disk mounted at
   `/home/homelab/.local/share/containers/storage`. Answer `n` to keep storage
   on the OS disk. Answer `y` to select a disk, then format it as XFS (new
   setup) or use an existing `xfs`/`ext4` filesystem. Formatting a disk
   requires typing `FORMAT` and the `/dev/disk/by-id/...` name. Treat that disk
   as permanently attached; do not unplug it while services run. Scripted
   runs can pass `--no-data-disk`, or `--data-disk /dev/disk/by-id/DEVICE` and
   optionally `--format-data-disk`. Non-TTY runs without those flags keep
   storage on the OS disk.

   Record the printed `age1pq1...` host recipient. Bootstrap creates the locked
   `homelab` account, installs Fedora's age and restic RPMs plus the
   checksum-verified SOPS RPM, clones the private repository, generates
   `/home/homelab/.config/sops/age/keys.txt`, installs the TCP 443 proxy and
   the daily host-tools update timer, and configures firewalld for the host's
   active default zone (e.g. `FedoraServer` on Fedora Server or `public` on
   Workstation; override with `--firewalld-zone`). The version
   command must report restic 0.19.1 or later. The generated `keys.txt` private
   identity is required to decrypt the existing secrets on a replacement host.
   Back it up in step 15. Never commit it.

8. Verify that the installed deploy credential can read the private repository:

   ```bash
   uid=$(id -u homelab)
   sudo runuser -u homelab -- \
     env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
     git -C /home/homelab/git/repository ls-remote origin refs/heads/main
   ```

   The command must print the `main` commit. The private deploy key at
   `/home/homelab/.ssh/id_ed25519` is required for unattended fetches. For a
   replacement host, create a new deploy key by repeating steps 3-5; restoring
   the old deploy key is optional.

9. On the operator workstation, generate the independent operator age identity
   and print its recipient:

   ```bash
   install -d -m 0700 ~/.config/sops/age
   test ! -e ~/.config/sops/age/operator.txt
   age-keygen -pq -o ~/.config/sops/age/operator.txt
   chmod 0600 ~/.config/sops/age/operator.txt
   age-keygen -y ~/.config/sops/age/operator.txt
   ```

   Back up `operator.txt` immediately to a separate encrypted/offline location.
   It is required to edit or recover secrets if the host identity is lost. Do
   not copy it to the container host and never commit it.

10. In Cloudflare, open **My Profile** > **API Tokens** > **Create Token** >
    **Create Custom Token**. Name it `Caddy HOSTNAME`. Add `Zone` > `Zone` >
    `Read` and `Zone` > `DNS` > `Edit`; under **Zone Resources**, include only
    the `BASE_DOMAIN` zone. Select **Continue to summary**, verify the two
    permissions and single-zone scope, select **Create Token**, and copy the
    token. These are the permissions required by the
    [Caddy Cloudflare module](https://github.com/caddy-dns/cloudflare#configuration).
    The token is shown once and will be encrypted by step 12.

11. Configure name resolution for every Caddy hostname: `bookmarks`, `git`,
    `home`, `home-zigbee`, `photos`, `contacts`, `search`,
    `syncthing`, and `vault`, all below
    `BASE_DOMAIN`.

    For public access, create a DNS-only wildcard `A` record named `*` pointing
    at the public IPv4 address and, if used, a DNS-only wildcard `AAAA` record
    pointing at the host IPv6 address. Forward TCP 443 and Syncthing TCP/UDP
    22000 at the router to the host. For LAN-only access, create the wildcard
    records in internal DNS pointing at the host's LAN address and do not
    create inbound router forwards. The Cloudflare zone and token are still
    required for ACME DNS-01 certificate issuance.

12. Before running secret initialization, have these values ready: the base
    domain, timezone, Zigbee router serial ID, S3 endpoint, region, bucket
    name, optional S3 prefix, the S3 key ID and secret, a unique restic
    repository password of at least 20 characters, the Cloudflare token from
    step 10, a bookmarks password, a Radicale username and password, and a
    Vaultwarden admin password. Save the chosen application passwords and the
    restic password in the operator password manager; application password
    hashes cannot be reversed. From the repository root on the operator
    workstation, initialize and push encrypted secrets using the host
    recipient printed in step 7 and the operator recipient printed in step 9:

    ```bash
    ./bin/init-secrets \
      --host-recipient age1pq1HOST... \
      --operator-recipient age1pq1OPERATOR...
    git add .sops.yaml secrets/secrets.sops.yaml
    git commit -m 'Initialize encrypted deployment secrets'
    git push origin main
    ```

    `secrets/secrets.sops.yaml` and `.sops.yaml` are required on a replacement
    host and are recovered by cloning the private repository.

    Re-run host bootstrap so it can pull the encrypted file, set the timezone,
    and install the Zigbee udev rule (`dialout` `0660`, no `uaccess`). If the
    first run already mounted a storage disk, omit the disk flags. Otherwise
    pass the same `--data-disk` / `--format-data-disk` or `--no-data-disk`
    choice:

    ```bash
    cd ~/podman-bootstrap/source
    sudo ./bin/bootstrap-host \
      --repo git@github.com:OWNER/REPOSITORY.git \
      --git-key ../github-deploy-key \
      --known-hosts ../github-known-hosts
    ```

13. Run the first reconciliation on the target host and verify it:

    ```bash
    uid=$(id -u homelab)
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      /home/homelab/git/repository/bin/reconcile
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      /home/homelab/current/bin/status
    ```

14. Initialize the encrypted restic repository exactly once and verify its
    configuration. This is deliberately not automatic: a missing repository
    or incorrect endpoint must never silently create a second backup history.

    ```bash
    uid=$(id -u homelab)
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      /home/homelab/current/bin/restic init
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      /home/homelab/current/bin/restic cat config
    ```

    Stop if either command fails. `restic init` must be run only for a new,
    empty repository prefix; use `cat config` without `init` when adopting an
    existing repository.

15. Run and verify the first encrypted S3 backup:

    ```bash
    uid=$(id -u homelab)
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      systemctl --user start homelab-backup.service
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      /home/homelab/current/bin/restic snapshots --latest 1
    sudo runuser -u homelab -- \
      env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
      /home/homelab/current/bin/status
    ```

    Follow the complete [encrypted S3 backup procedure](docs/backups.md) for
    provider-specific settings and checks. Do not treat the installation as
    recoverable until the host age identity, operator age identity, named
    volumes have verified backups.

16. Remove the target host's temporary bootstrap copy after the backup has
    been verified. Keep or destroy the operator-side deploy-key copy according
    to the backup inventory below; the installed copy remains under the
    `homelab` account.

The first deployment builds the two custom images, pulls every upstream image, and
starts all application targets. It creates empty application state.

Complete the required Vaultwarden setup immediately:

1. Open `https://vault.BASE_DOMAIN`, register the owner account, and verify the
   login.
2. Change `Environment=SIGNUPS_ALLOWED=true` to `false` in
   `quadlet/applications/vaultwarden/vaultwarden.container`.
3. Commit and push the change.
4. Run `~/current/bin/reconcile` as `homelab`, or wait for the timer.
5. Verify that the owner can still log in and that new registration is closed.

The Vaultwarden owner account is stored in `homelab-vaultwarden-data`; its
encrypted volume snapshot is required when restoring onto a new host.

## GitOps operation

`homelab-reconcile.timer` fetches `origin/main` every five minutes. Each update
is staged as `/home/homelab/releases/<commit>` and validated before the
`/home/homelab/current` symlink is switched.

An image update is a normal reviewed Git change:

```ini
[Container]
Image=docker.io/example/application:2.0.0@sha256:...
```

After merge, reconciliation pre-pulls the exact image and restarts only the
affected application target. Shared releases such as Immich are grouped by
Renovate. `AutoUpdate=registry` is deliberately not used.

The self-hosted Renovate workflow runs every day at 04:17 UTC. Configure it
once:

1. Sign in as the dedicated bot account that has access to this private
   repository.
2. Open **Settings** > **Developer settings** > **Personal access tokens** >
   **Fine-grained tokens** > **Generate new token**. Limit repository access
   to this repository. Grant read/write access to Contents, Issues, Pull
   requests, Commit statuses, and Workflows, plus read access to Dependabot
   alerts. Generate and copy the token.
3. In the repository, open **Settings** > **Secrets and variables** >
   **Actions** > **New repository secret**. Set the name to `RENOVATE_TOKEN`,
   paste the bot token, and save it.
4. Open **Actions** > **Renovate** > **Run workflow** > **Run workflow**.
5. Verify that the run succeeds and that Renovate can open a pull request.

A classic token with the `repo` and `workflow` scopes is an alternative. Limit
either token to this repository. The Actions secret remains in GitHub and is
not required on a replacement container host.

The workflow deliberately does not use the automatic `GITHUB_TOKEN`:
pull requests created with that token do not reliably trigger the validation
workflow. It fails with a setup message when `RENOVATE_TOKEN` is absent. The
workflow is restricted to scheduled and manual events, so the secret is never
exposed to pull-request code.

Require the `validate`, `host-tools (amd64)`, `host-tools (arm64)`, and `e2e`
checks in the `main` branch protection rule. A `select` job maps the Git diff
onto those checks: CI, docs, incubator, Renovate-workflow, encrypted-secret,
Home Assistant automation, and validate-only test changes skip Podman, custom
image builds, and host-tool tests, so `e2e` can pass in seconds. Workload
changes run only the affected workloads. Custom image Containerfiles build
only the matching image. Host-tool metadata runs the architecture tests and
the complete Podman suite. Global deployment changes still run the complete
real Podman E2E suite. Keep approval and merge manual; passing checks do not
automatically merge an update.

The included `renovate.json` understands Quadlet `Image=` entries and the
custom image build inputs. Its Docker digest pinning and `currentDigest`
capture mean Renovate changes the SHA-256 digest together with a tag, and also
proposes digest-only updates when a tag is republished. Custom managers cover
the Caddy `xcaddy` modules, Radicale's pinned Alpine packages, and the
architecture-specific SOPS release assets and checksums in
`config/host-tools.env`. Fedora-managed age and Restic packages are not
controlled by this GitOps pin. Container and host-tool updates are never
automerged; after review and merge, deployment remains the responsibility of
the GitOps reconciler. The workflow action and Renovate container version are
pinned and are themselves managed by Renovate.

Useful commands as the `homelab` user:

```bash
~/current/bin/reconcile --dry-run
~/current/bin/reconcile
~/current/bin/status
systemctl --user status homelab.target
journalctl --user -u homelab-reconcile.service
journalctl --user -u caddy.service
podman ps
~/current/bin/security-audit
```

If Git, SOPS, validation, a registry, or a local build fails before activation,
the current release continues running. If systemd reload or a unit health check
fails after the `current` symlink has already moved, reconcile restores the
previous `current` target and reloads units; that symlink rollback is not a
database downgrade, and named-volume major migrations already applied by
`migrate-databases` are not reversed. Runtime failures after a stateful
service starts are also not automatically rolled back, because its database
may already have migrated.

### Automated PostgreSQL and MariaDB major version updates

When Renovate updates a PostgreSQL or MariaDB container image across major
versions, `bin/migrate-databases` runs during `reconcile` before the new
systemd application target starts. It discovers only
`*-postgres.container` and `*-mariadb.container` units. Thin wrappers
`bin/migrate-postgres` and `bin/migrate-mariadb` select one engine for
manual use.

Shared steps:

1. Detect a mismatch between the on-disk major (`PG_VERSION`, or
   `mariadb_upgrade_info` / `mysql_upgrade_info`) and the target image.
2. Stop the owning application target and database unit, then fail if either
   is still active or if any container still has the data volume mounted.
3. Dump the database with an ephemeral rootless `--network none` container
   using the previous image, and write a raw tarball of the data directory
   into `~/.local/state/homelab/{postgres,mariadb}-upgrades/` before wiping
   the volume.
4. Re-initialize the volume with the new image, restore the dump, and verify
   it (`SELECT current_database()` for PostgreSQL, schema presence for
   MariaDB).
5. On success, keep the logical dump and delete the bulky raw tarball. If
   restoration or verification fails, roll back from the state-dir tarball
   (not a temp directory).

PostgreSQL uses a custom-format `pg_dump` / `pg_restore`. MariaDB dumps
logical users with `--system=users`, then application databases with
`mariadb-dump --all-databases` as root via the imported
`MYSQL_ROOT_PASSWORD` secret, omitting the `mysql` and `sys` schemas so a
major upgrade does not restore a physical `mysql.proc` table into the new
version. It does not mount `docker-entrypoint-initdb.d` seed SQL during the
upgrade. Downgrades are refused.

The migration tool can also be run or inspected manually:

```bash
~/current/bin/migrate-databases --check
~/current/bin/migrate-databases --dry-run
~/current/bin/migrate-postgres --workload forgejo
~/current/bin/migrate-postgres --workload immich
```

### Hardening an existing host

Hosts installed by an older revision have `container_use_devices` enabled
globally. Before deploying the hardened Quadlets, perform the one required
host migration as an administrator:

```bash
sudo dnf install -y container-selinux
test "$(getenforce)" = Enforcing
sudo setsebool -P container_use_devices off
getsebool container_use_devices
```

The final command must report `off`. Reconciliation will otherwise stop before
restarting containers. After deployment, run `~/current/bin/security-audit`
as `homelab`, exercise every application, and check for new SELinux denials:

```bash
sudo ausearch -m AVC,USER_AVC -ts recent
```

Do not resolve a denial by disabling SELinux, using `spc_t`, enabling nested
labels, or restoring the default capability set. Add only the specific
writable mount, file label, or allowlisted capability demonstrated necessary.

## Secret rotation

Edit the encrypted file only through SOPS:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt \
  sops secrets/secrets.sops.yaml
git add secrets/secrets.sops.yaml
git commit -m 'Rotate deployment secrets'
git push origin main
```

The reconciler replaces Podman secrets and recreates their declared consumers.
The post-quantum age host identity is mode `0600` under
`/home/homelab/.config/sops/age/keys.txt`. Back it up separately from the
operator identity. To add or remove recipients, update `.sops.yaml` and run:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt \
  sops updatekeys secrets/secrets.sops.yaml
```

Repository validation requires
exactly two `age1pq1...` recipients in both the creation rule and encrypted
SOPS metadata, preventing a later downgrade to classical age keys. An age
private identity cannot be recreated from its recipient. Restore the exact
`keys.txt` from backup on a replacement host.

Home Assistant `.storage`, Forgejo state, and credentials created through
application UIs are application-managed state, not deployment secrets.

## Backup and recovery

The canonical procedures are:

- [Encrypted S3 setup and manual backups](docs/backups.md)
- [Restore onto a replacement host](docs/host-migration.md)
- [Migrate an old `main` Docker snapshot to Quadlets](docs/legacy-main-to-quadlets.md)
- [Restore one older volume on the existing host](docs/restore-volume.md)

The automated snapshots are encrypted locally, incremental, and deduplicated.
The first run uploads all selected data; later runs upload only new chunks
while remaining complete point-in-time snapshots.

When migrating between hosts, amd64 hosts remain native. An arm64 replacement
host completes the QEMU setup during `bootstrap-host` before the first
reconciliation, and native multi-architecture images follow the host's native
architecture.

## Backup inventory

| Item | Backup requirement | Replacement-host action |
| --- | --- | --- |
| Private GitHub repository | Keep all changes pushed. An independent mirror is optional. | Clone it with a read-only deploy key. |
| `.sops.yaml` and `secrets/secrets.sops.yaml` | Required; keep them committed in the private repository. They include the domain, timezone, Zigbee serial ID, backup location, and owner-scoped Forgejo Runner secret/UUID. | Clone them from GitHub; the host age identity decrypts them. Update the Zigbee serial ID through SOPS first if the replacement hardware differs. Reuse the committed runner registration and never run it concurrently on the old and replacement hosts. |
| Host age identity: `/home/homelab/.config/sops/age/keys.txt` | Required; store encrypted/offline. | Restore the exact file with `--host-age-key`. Do not generate a replacement when restoring existing SOPS secrets. |
| Operator age identity: `~/.config/sops/age/operator.txt` | Required; store encrypted/offline, separately from the host identity. | Keep it on the operator workstation. It is the recovery identity if the host copy is lost. |
| GitHub deploy private key | Optional. It is an unencrypted secret. | Prefer a new key and a new read-only GitHub deploy-key entry. Restore the old key only if intentionally retaining it. |
| Verified `github-known-hosts` | No. | Recreate it and verify it against GitHub's published fingerprint. |
| Cloudflare and generated deployment credentials | Required in encrypted form; keep `secrets/secrets.sops.yaml` pushed. | No separate host copy is required. SOPS decrypts them from Git. |
| Chosen bookmarks, Radicale, and Vaultwarden plaintext passwords | Keep in the operator password manager. | They are not host bootstrap inputs. Their hashes come from Git and application accounts come from volume backups. |
| `RENOVATE_TOKEN` | Keep it as a GitHub Actions repository secret. | It is not copied to or required by the container host. |
| S3 access key and restic repository password | Required in SOPS and the operator password manager. | Decrypt them with the offline operator identity to access backups after host loss. |
| Deployed Git commit | Included in every restic snapshot. | Verify that it exists in Git and is an ancestor of the revision being deployed. |
| Active `homelab-*` Podman named volumes | Included in every restic snapshot. | Create empty named volumes and restore their snapshot subtrees before first reconciliation. Inactive incubator volumes are outside this inventory. |
| Forgejo Runner account, graphroot, containers, and `/var/lib/homelab/forgejo-runner-storage.xfs` | No; CI execution state is disposable and must not cross hosts. | Run bootstrap with `--defer-forgejo-runner` during restoration. Bootstrap creates a fresh bounded graphroot; rerun it without the option only at final cutover. |
| Releases, rendered configs, installed binaries, systemd links, firewall rules, and the `zigbee-router` symlink | No. | `bootstrap-host` and `reconcile` recreate them. |

Application accounts and settings created through a UI are stored in the named
volumes; encrypted deployment credentials are stored in Git. Git reconciliation
never deletes named volumes.

## Legacy offline archive fallback

The following removable-media workflow is retained only as an independent
offline fallback. Use the automated restic procedure above for routine backups.

This is a cold backup of every application volume. It stops all applications
so PostgreSQL, MariaDB, SQLite, Valkey, and file data are consistent.

1. Mount an encrypted backup destination. Create a host-specific directory
   writable only by `homelab`:

   ```bash
   sudo install -d -m 0700 -o homelab -g homelab \
     /MOUNTED/ENCRYPTED/BACKUP/HOSTNAME-YYYYMMDDTHHMMSSZ
   ```

2. Open a `homelab` login shell and set its user systemd runtime directory:

   ```bash
   sudo -iu homelab
   set -Eeuo pipefail
   export XDG_RUNTIME_DIR="/run/user/$(id -u)"
   cd ~/current
   ```

3. Stop reconciliation and every application target:

   ```bash
   mapfile -t backup_apps < <(jq -r 'keys[]' manifests/applications.json)
   systemctl --user stop homelab-reconcile.timer homelab-backup.timer
   while systemctl --user is-active --quiet homelab-reconcile.service; do
     sleep 1
   done
   systemctl --user stop homelab.target
   for app in "${backup_apps[@]}"; do
     systemctl --user stop "homelab-$app.target"
   done
   test -z "$(podman ps --quiet)"
   ```

   Do not continue unless the final command succeeds. The `homelab` account is
   dedicated to this deployment, so any running container means the backup is
   not cold.

4. Archive every active named volume and the host age identity:

   ```bash
   backup_root=/MOUNTED/ENCRYPTED/BACKUP/HOSTNAME-YYYYMMDDTHHMMSSZ
   umask 077
   install -d -m 0700 "$backup_root/volumes"
   : > "$backup_root/volume-list.txt"
   while IFS= read -r app; do
     podman volume ls \
       --filter "label=io.containers.systemd.application=$app" \
       --format '{{.Name}}' >> "$backup_root/volume-list.txt"
   done < <(jq -r 'keys[]' manifests/applications.json)
   sort -u -o "$backup_root/volume-list.txt" "$backup_root/volume-list.txt"
   sed -n 's/^VolumeName=//p' quadlet/volumes/*.volume \
     | sort > "$backup_root/expected-volume-list.txt"
   diff -u "$backup_root/expected-volume-list.txt" \
     "$backup_root/volume-list.txt"

   while IFS= read -r volume; do
     volume_path=$(podman volume inspect --format '{{.Mountpoint}}' "$volume")
     podman unshare tar --acls --xattrs --selinux \
       -C "$volume_path" -czf "$backup_root/volumes/$volume.tar.gz" .
   done < "$backup_root/volume-list.txt"

   install -m 0600 ~/.config/sops/age/keys.txt "$backup_root/host-age-keys.txt"
   install -m 0600 ~/.local/state/homelab/deployed-commit \
     "$backup_root/deployed-commit.txt"
   (
     cd "$backup_root"
     find . -type f ! -name SHA256SUMS -print0 \
       | sort -z \
       | xargs -0 sha256sum > SHA256SUMS
   )
   ```

5. Verify every archive and checksum before restarting services:

   ```bash
   (
     cd "$backup_root"
     sha256sum --check SHA256SUMS
   )
   while IFS= read -r volume; do
     tar -tzf "$backup_root/volumes/$volume.tar.gz" >/dev/null
   done < "$backup_root/volume-list.txt"
   ```

6. Restart the deployment and leave the `homelab` shell:

   ```bash
   systemctl --user start homelab.target homelab-reconcile.timer homelab-backup.timer
   ~/current/bin/status
   exit
   ```

   If any command in steps 3-5 fails, correct the backup error or discard the
   incomplete backup, then run this restart step before leaving the host.

7. On the operator workstation, copy
   `~/.config/sops/age/operator.txt` to a different encrypted/offline backup.
   Verify that the copied identity prints the operator recipient recorded in
   `.sops.yaml`:

   ```bash
   age-keygen -y /ENCRYPTED/OFFLINE/BACKUP/operator.txt
   ```

8. Copy the completed host backup off the container host. Verify
   `SHA256SUMS` at the destination. Keep at least one backup created before
   each database-migrating application upgrade.

## Legacy offline-archive restore

For S3/restic snapshots, use the canonical replacement-host guide above. The
following procedure applies only to archives created by the legacy fallback.

Do not run an initial reconciliation before restoring the volumes.

1. On the operator workstation, verify the selected backup:

   ```bash
   cd /RESTORED/BACKUP/HOSTNAME-YYYYMMDDTHHMMSSZ
   sha256sum --check SHA256SUMS
   age-keygen -y host-age-keys.txt
   ```

   The second command must print the host recipient present in `.sops.yaml`
   and `secrets/secrets.sops.yaml`. If it does not, stop.

2. Create a fresh host deploy key and verified `github-known-hosts` by repeating
   initial-installation steps 3-5. Add the fresh public key to **Settings** >
   **Deploy keys** in the same private GitHub repository. Do not remove the old
   host's deploy key yet if the old host is still in service.

3. Attach the Zigbee coordinator to the new host and verify that the configured
   device exists:

   ```bash
   ls -l /dev/serial/by-id/
   ```

   If its serial ID differs, edit `site.homeassistant_zigbee_router_serial_id`
   in `secrets/secrets.sops.yaml` with SOPS, commit, and push that change
   before continuing.

4. From the repository root on the operator workstation, copy the current
   trusted working tree and fresh GitHub inputs to the new host:

   ```bash
   ssh ADMIN@NEW_HOST \
     'install -d -m 0700 ~/podman-bootstrap/source ~/podman-bootstrap/volumes'
   rsync -a --exclude .git ./ ADMIN@NEW_HOST:podman-bootstrap/source/
   scp /SECURE/PATH/homelab-bootstrap/github-deploy-key \
     /SECURE/PATH/homelab-bootstrap/github-known-hosts \
     ADMIN@NEW_HOST:podman-bootstrap/
   ```

   Copy the verified backup files from the backup directory:

   ```bash
   scp host-age-keys.txt deployed-commit.txt volume-list.txt \
     expected-volume-list.txt SHA256SUMS \
     ADMIN@NEW_HOST:podman-bootstrap/
   rsync -a volumes/ ADMIN@NEW_HOST:podman-bootstrap/volumes/
   ssh ADMIN@NEW_HOST 'chmod 0600 ~/podman-bootstrap/github-* ~/podman-bootstrap/host-age-keys.txt ~/podman-bootstrap/volumes/*'
   ssh ADMIN@NEW_HOST \
     'cd ~/podman-bootstrap && sha256sum --check SHA256SUMS'
   ```

5. On the new host, run bootstrap with the backed-up host identity:

   ```bash
   cd ~/podman-bootstrap/source
   sudo ./bin/bootstrap-host \
     --repo git@github.com:OWNER/REPOSITORY.git \
     --git-key ../github-deploy-key \
     --known-hosts ../github-known-hosts \
     --host-age-key ../host-age-keys.txt \
     --data-disk /dev/disk/by-id/DEVICE
   ```

   Add `--format-data-disk` only for an empty replacement disk. If the original
   data disk moved with the host, omit it. Use `--no-data-disk` to keep storage
   on the OS disk. Restore the volume archives only after
   `/home/homelab/.local/share/containers/storage` is mounted.

   The printed host recipient must equal the value verified in step 1.
   `--host-age-key` refuses to overwrite a different existing host identity.

6. Stage only the application backup files for the `homelab` account:

   ```bash
   sudo install -d -m 0700 -o homelab -g homelab /home/homelab/restore/volumes
   sudo install -m 0600 -o homelab -g homelab \
     ~/podman-bootstrap/volume-list.txt /home/homelab/restore/volume-list.txt
   sudo install -m 0600 -o homelab -g homelab \
     ~/podman-bootstrap/deployed-commit.txt /home/homelab/restore/deployed-commit.txt
   sudo cp ~/podman-bootstrap/volumes/*.tar.gz /home/homelab/restore/volumes/
   sudo chown homelab:homelab /home/homelab/restore/volumes/*.tar.gz
   sudo chmod 0600 /home/homelab/restore/volumes/*.tar.gz
   ```

7. Create and restore every volume before starting an application:

   ```bash
   sudo -iu homelab
   set -Eeuo pipefail
   export XDG_RUNTIME_DIR="/run/user/$(id -u)"
   cd ~/git/repository
   backup_commit=$(<"$HOME/restore/deployed-commit.txt")
   git cat-file -e "$backup_commit^{commit}"
   git merge-base --is-ancestor "$backup_commit" origin/main
   while IFS= read -r volume_file; do
     volume=$(sed -n 's/^VolumeName=//p' "$volume_file")
     label=$(sed -n 's/^Label=//p' "$volume_file")
     archive="$HOME/restore/volumes/$volume.tar.gz"
     grep -Fxq "$volume" "$HOME/restore/volume-list.txt"
     test -f "$archive"
     if podman volume exists "$volume"; then
       printf 'Refusing to overwrite existing volume: %s\n' "$volume" >&2
       exit 1
     fi
     podman volume create --label "$label" "$volume" >/dev/null
     volume_path=$(podman volume inspect --format '{{.Mountpoint}}' "$volume")
     podman unshare tar --acls --xattrs --selinux \
       -C "$volume_path" -xzf "$archive"
   done < <(find quadlet/volumes -type f -name '*.volume' | sort)

   sops --decrypt secrets/secrets.sops.yaml >/dev/null
   ```

   All commands must succeed. A failed ancestry check means the selected data
   backup does not lead forward to the current `main`; select the matching Git
   revision before continuing. If SOPS decryption fails, do not generate
   another host identity; reinstall the correct `host-age-keys.txt` backup.

8. Run reconciliation and verification:

   ```bash
   ~/git/repository/bin/reconcile
   ~/current/bin/status
   systemctl --user status homelab-reconcile.timer
   exit
   ```

9. Verify application logins and application data. Verify that Git fetch works:

   ```bash
   uid=$(id -u homelab)
   sudo runuser -u homelab -- \
     env HOME=/home/homelab XDG_RUNTIME_DIR="/run/user/$uid" \
     git -C /home/homelab/git/repository fetch --prune origin main
   ```

10. Move the wildcard DNS records and any router forwards from the old host's
    address to the new host's address. Verify HTTPS access and Syncthing
    connectivity from the intended networks.

11. Remove `/home/homelab/restore` and `~/podman-bootstrap` only after the new
    host and an independent copy of the backup have been verified. In GitHub,
    remove the retired host's deploy key under **Settings** > **Deploy keys**.

If the host age identity backup is unavailable but the operator identity still
works, bootstrap without `--host-age-key`, replace the old host recipient in
`.sops.yaml` with the new printed recipient, then run this on the operator
workstation:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/operator.txt \
  sops updatekeys secrets/secrets.sops.yaml
git add .sops.yaml secrets/secrets.sops.yaml
git commit -m 'Replace lost host age recipient'
git push origin main
```

Do this before reconciling. This is recipient rotation, not recreation of the
lost private key. If both identities are lost, the encrypted deployment
secrets cannot be recovered and must be replaced.

## Host-managed updates

SOPS and Forgejo Runner are manually fetched host tools, so their release tags
and amd64/arm64 checksums are committed in `config/host-tools.env`. Renovate
checks the upstream stable releases daily and opens pull requests. After the pull
request passes the required host-tool tests and the affected-workload E2E suite
(or the full suite for global changes) and is merged, `homelab-reconcile.timer`
publishes the new metadata through `current`.

`homelab-host-tools-update.timer` then runs daily at 02:00 in the host timezone
with a persistent catch-up run. Its root-owned helpers are installed by
`bootstrap-host`; the helpers read only validated metadata and derive the fixed
upstream download URLs and artifact names. They never execute code from the
mutable Git checkout. A failed download, checksum, metadata, or installation
leaves the previously installed version in place. Forgejo Runner updates use
the upstream release's architecture-specific checksum files, replace the binary
atomically, and restart the runner service only after a successful update.
Upstream releases are therefore proposed automatically but remain review-gated;
there is no unattended update directly from an upstream release. Inspect them with:

```bash
systemctl status homelab-host-tools-update.timer
systemctl status homelab-host-tools-update.service
rpm -q sops
forgejo-runner --version
```

For an existing host that predates this timer, rerun the reviewed `bootstrap-host`
command from the initial-installation procedure once. This installs the fixed
helpers and timer; it does not grant the Git reconciler root access.

The socket proxy is also intentionally outside rootless GitOps. After reviewing
a change under `systemd/system`, reinstall it explicitly:

```bash
sudo install -m 0644 systemd/system/caddy-https-proxy.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart caddy-https-proxy.socket
```

SELinux policy under `selinux/` is compiled and loaded by `bootstrap-host`.
Re-run that command after a policy change. The Git reconciler does not apply it.

The fixed host-tool helpers, socket proxy, and that SELinux module are the only
host-root integration points. The Git reconciler still has no sudo access, and
the host-tool helpers accept only release metadata for the fixed upstream
releases rather than running repository scripts as root.

## Forgejo Actions runner

Forgejo Actions allows running CI/CD workflows triggered by Git events in Forgejo.
Because CI workflows execute arbitrary code, they are strictly quarantined from
production workloads.

### Security boundary and isolation model

1. **Dedicated Host Account**: The runner executes under a dedicated system user
   account `forgejo-runner` with a locked password and no login credentials.
   It has no sudo access or group memberships in `wheel`, `root`, or `homelab`.
2. **Subordinate UID/GID Segregation**: Subordinate IDs are allocated from
   `200000-265535`, strictly non-overlapping with the `homelab` production range
   (`100000-165535`).
3. **Independent Podman Runtime & Storage**: The runner uses its own rootless
   Podman instance (`/home/forgejo-runner/.local/share/containers/storage`) and
   systemd user manager. It has no access to the `homelab` account's Podman socket
   (`/run/user/<HUID>/podman/podman.sock`), storage, secrets, or rendered configs.
   Its graphroot is a dedicated 20 GiB XFS filesystem backed by
   `/var/lib/homelab/forgejo-runner-storage.xfs`, preventing CI from filling the
   production filesystem without a fixed ceiling.
4. **Hardened Runner Configuration**:
   - `capacity: 1` limits concurrent execution to a single job.
   - `docker_host: "-"` blocks jobs from mounting or accessing the runner's own
     Podman daemon socket.
   - `privileged: false` enforces unprivileged container execution.
   - `valid_volumes: []` blocks jobs from mounting arbitrary host paths.
   - `cache.enabled: false` prevents cache poisoning between workflow runs.
   - the Node 26 Trixie job image is digest-pinned, forcibly refreshed before
     use, and old unused resources are pruned weekly by the runner-only user timer.
5. **Network & Egress Isolation**: The host service `homelab-forgejo-runner-egress.service`
   loads nftables egress rules matching `meta skuid "forgejo-runner"`. DNS is
   allowed only to resolvers listed by the host. The resolved Forgejo addresses
   receive a TCP 443 exception; all other outbound traffic destined for
   RFC1918 private subnets (`10.0.0.0/8`, `172.16.0.0/12`,
   `192.168.0.0/16`), loopback (`127.0.0.0/8`, `::1/128`), and IPv6 ULAs (`fc00::/7`).
   The runner communicates with Forgejo exclusively over HTTPS via `git.${BASE_DOMAIN}`.
6. **Resource Limits**: Both the daemon and the complete `user-<RUID>.slice`
   enforce `MemoryMax=16G`, `CPUQuota=400%`, and `TasksMax=2048`. The user-slice
   limit covers the Podman API service, job containers, service containers, and
   the runner daemon together. Each job container is additionally limited to four
   CPUs, 16 GiB of memory, and 1024 PIDs.

### Registration and operation

Runners are registered at owner scope rather than repository or global scope.
Every repository belonging to that Forgejo user or organization may schedule
jobs on the runner, while repositories owned by other accounts cannot.

1. **Register the runner**:
   On the host or management environment with access to the running `forgejo` container:

   ```bash
   ./bin/register-forgejo-runner --scope OWNER
   ```

   This executes an owner-scoped offline registration via `forgejo-cli` inside
   the Forgejo container using the secret passed via stdin (`--secret-stdin`).
   An empty/global scope and an `OWNER/REPOSITORY` scope are rejected.
   `bin/init-secrets` generated the secret; registration records the returned
   UUID securely in `secrets/secrets.sops.yaml`.

2. **Commit and deploy**:
   Commit the updated `secrets/secrets.sops.yaml` and deploy to the host.

3. **Apply and start the runner**:
   Run `sudo ./bin/bootstrap-host ...`. Bootstrap renders the runner configuration
   at `/home/forgejo-runner/.config/forgejo-runner/config.yaml`, registers the systemd
   user service, and starts `forgejo-runner.service`.

4. **Verify status**:

   ```bash
   runner_uid=$(id -u forgejo-runner)
   sudo runuser -u forgejo-runner -- env HOME=/home/forgejo-runner \
     XDG_RUNTIME_DIR=/run/user/$runner_uid \
     DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$runner_uid/bus \
     systemctl --user status podman.socket forgejo-runner.service
   systemctl status homelab-forgejo-runner-egress.service
   sudo runuser -u forgejo-runner -- env HOME=/home/forgejo-runner \
     XDG_RUNTIME_DIR=/run/user/$runner_uid bash -c 'cd "$HOME"; exec podman ps -a'
   ```

Runner configuration, job-image, nftables, user-slice, or storage-policy changes
are host-integration changes. Re-run the reviewed `bootstrap-host` command after
merging them. Binary-only Forgejo Runner updates are installed by the daily
host-tools timer and restart the daemon automatically.

To disable and roll back Actions execution without changing Forgejo data:

```bash
runner_uid=$(id -u forgejo-runner)
sudo runuser -u forgejo-runner -- env HOME=/home/forgejo-runner \
  XDG_RUNTIME_DIR=/run/user/$runner_uid \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$runner_uid/bus \
  systemctl --user disable --now forgejo-runner.service forgejo-runner-prune.timer podman.socket
sudo systemctl disable --now homelab-forgejo-runner-egress.service
```

Unregister the runner in Forgejo before deleting its bounded storage image or
account. Forgejo may remain Actions-enabled with no online runner.
