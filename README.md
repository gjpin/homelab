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
| [Supernote Private Cloud](https://support.supernote.com/setting-up-your-own-supernote-private-cloud-beta) | supernote.${BASE_DOMAIN} | Private Cloud for Supernote | No |
| [Syncthing](https://github.com/syncthing/syncthing) | syncthing.${BASE_DOMAIN} | Continuous file synchronization | No |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | vault.${BASE_DOMAIN} | Unofficial Bitwarden-compatible server | No |

The table lists user-facing services. Supporting databases, caches, MQTT, and
worker containers stay on internal or dedicated backend networks and are not
directly exposed. “Yes” means the service has Internet egress; “No” means all
of its attached Podman networks are internal. Inbound public access is still
limited to the Caddy HTTPS proxy, plus Syncthing's documented TCP/UDP 22000
protocol ports.

Supernote's `notelib` retains a separate network for service-specific
isolation. It is now internal as well; the repository history does not record
an upstream dependency that requires Internet access, so the historical
`egress` name should not be interpreted as an exception to the no-egress
policy.

## Security model

- All containers run under the dedicated, password-locked `homelab` account.
- The Git reconciler has no sudo access and cannot modify host system units.
- Only TCP 443 and Syncthing TCP/UDP 22000 are exposed externally.
- Application networks use strictly isolated deterministic `/24` ranges within
  `10.200.0.0/16`. Caddy joins edge networks only; database, cache, and MQTT
  networks are internal. Radicale, Supernote, Syncthing, and Vaultwarden have
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
- SELinux must remain enforcing. Normal containers use `container_t` with
  per-container MCS separation. Only Zigbee2MQTT uses `container_device_t`, and
  the global `container_use_devices` boolean remains off.
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
  `container-selinux`, `curl`, `diffutils`, `firewalld`, `fuse-overlayfs`,
  `gettext-envsubst`, `gawk`, `git`, `iproute`, `jq`, `libselinux-utils`,
  `openssh-clients`, `passt`, `podman`, `policycoreutils`, `python3`,
  `ripgrep`, `shadow-utils`, `systemd`, `tar`, and `util-linux`. The script
  also provisions valid `homelab` subordinate-ID ranges and installs the
  official SOPS v3.13.3 RPM (`sops-3.13.3-1.x86_64.rpm` or
  `sops-3.13.3-1.aarch64.rpm`) after verifying its pinned SHA-256 checksum and
  RPM metadata.
- On arm64, bootstrap installs Fedora's `qemu-user-binfmt` and
  `qemu-user-static-x86` packages and enables `systemd-binfmt`. The native
  multi-architecture images follow the host; Supernote's amd64-only `notelib`
  and `supernote-service` images run under QEMU. Bootstrap fails if the
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
   root, configure the site, validate it, and push the initial commit:

   ```bash
   cd /PATH/TO/homelab/podman
   git init -b main
   vi config/site.env
   ./bin/validate
   ./tests/static.sh
   git add .
   git commit -m 'Initialize Podman homelab'
   git remote add origin git@github.com:OWNER/REPOSITORY.git
   git push -u origin main
   ```

   Set `BASE_DOMAIN`, `TIMEZONE`, `HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID`,
   and the four `BACKUP_S3_*` values in `config/site.env`. The GitHub
   repository is required on every replacement host; no separate repository
   backup is required if GitHub remains available and contains every committed
   change.

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
     --known-hosts ../github-known-hosts \
     --firewalld-zone public
     /usr/bin/restic version
     /usr/bin/age --version
     /usr/bin/sops --version
   ```

   Record the printed `age1pq1...` host recipient. Bootstrap creates the locked
   `homelab` account, installs Fedora's age and restic RPMs plus the
   checksum-verified SOPS v3.13.3 RPM, clones the private repository, generates
   `/home/homelab/.config/sops/age/keys.txt`, installs the TCP 443 proxy, and
   configures firewalld. The version command must report restic 0.19.1 or
   later. The generated `keys.txt` private identity is required
   to decrypt the existing secrets on a replacement host. Back it up in step
   15. Never commit it.

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
    `home`, `home-zigbee`, `photos`, `contacts`, `search`, `supernote`,
    `syncthing`, and `vault`, all below
    `BASE_DOMAIN`.

    For public access, create a DNS-only wildcard `A` record named `*` pointing
    at the public IPv4 address and, if used, a DNS-only wildcard `AAAA` record
    pointing at the host IPv6 address. Forward TCP 443 and Syncthing TCP/UDP
    22000 at the router to the host. For LAN-only access, create the wildcard
    records in internal DNS pointing at the host's LAN address and do not
    create inbound router forwards. The Cloudflare zone and token are still
    required for ACME DNS-01 certificate issuance.

12. Before running secret initialization, have these values ready: the S3 key
    ID and secret, a unique restic repository password of at least 20
    characters, the Cloudflare token from step 10, a bookmarks password, a
    Radicale username and password, and a Vaultwarden admin password. Save
    the chosen application passwords and the restic password in the operator
    password manager; application password hashes cannot be reversed. From the
    repository root on the operator workstation, initialize and push encrypted
    secrets using the host recipient printed in step 7 and the operator
    recipient printed in step 9:

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

The first deployment downloads and checksum-verifies the Supernote database
bootstrap SQL, builds the two custom images, pulls every upstream image, and
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

The included `renovate.json` understands Quadlet `Image=` entries and the
custom image build inputs. Its Docker digest pinning and `currentDigest`
capture mean Renovate changes the SHA-256 digest together with a tag, and also
proposes digest-only updates when a tag is republished. Custom managers cover
the Caddy `xcaddy` modules, Radicale's pinned Alpine packages, and the
architecture-specific release assets and checksums used by the age, SOPS, and
Restic installers. Container updates are never automerged; after review and
merge, deployment remains the responsibility of the GitOps reconciler. The
workflow action and Renovate container version are pinned and are themselves
managed by Renovate.

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
the current release continues running. Runtime failures are not automatically
rolled back after a stateful service starts because its database may already
have migrated.

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
- [Restore one older volume on the existing host](docs/restore-volume.md)

The automated snapshots are encrypted locally, incremental, and deduplicated.
The first run uploads all selected data; later runs upload only new chunks
while remaining complete point-in-time snapshots.

When migrating between hosts, amd64 hosts remain native. An arm64 replacement
host must complete the QEMU setup during `bootstrap-host` before the first
reconciliation; the reconciliation and security checks refuse to start the
Supernote stack unless `qemu-x86_64-static` and its enabled x86_64 binfmt
registration are available. The two Supernote units explicitly select amd64;
all other images use the host's native architecture.

## Backup inventory

| Item | Backup requirement | Replacement-host action |
| --- | --- | --- |
| Private GitHub repository | Keep all changes pushed. An independent mirror is optional. | Clone it with a read-only deploy key. |
| `.sops.yaml` and `secrets/secrets.sops.yaml` | Required; keep them committed in the private repository. | Clone them from GitHub; the host age identity decrypts them. |
| `config/site.env` | Required; keep it committed in the private repository. | Clone it from GitHub. Update the Zigbee serial ID first if the replacement hardware differs. |
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

   If its serial ID differs, update `HOMEASSISTANT_ZIGBEE_ROUTER_SERIAL_ID` in
   `config/site.env`, commit, and push that change before continuing.

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
     --firewalld-zone public
   ```

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

The socket proxy is intentionally outside rootless GitOps. After reviewing a
change under `systemd/system`, reinstall it explicitly:

```bash
sudo install -m 0644 systemd/system/caddy-https-proxy.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart caddy-https-proxy.socket
```

This separation prevents a compromised Git credential from becoming a root
execution path.
