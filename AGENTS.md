# Agent instructions

This repository is a rootless Podman Quadlet deployment. A container or
workload change is incomplete until it has real Podman E2E coverage and passes
the repository's security and topology checks.

Keep this file current when onboarding an application or service. A new
workload must add an entry to the workload inventory below. A new service in an
existing workload must update that workload's entry with its units,
dependencies, networks, persistence, secrets, UI exposure, readiness mode, and
security exceptions. Update the general checklist when the repository policy
changes.

## Non-negotiable deployment rules

- Run services through rootless Podman and the systemd user manager owned by
  the locked `homelab` account. Do not add host-root or privileged execution.
- Pin every upstream container image and every `Containerfile` base image by
  immutable `@sha256:` digest. Do not use `:latest`, floating tags, or
  `AutoUpdate=`.
- Pin manually fetched host-tool releases and every architecture-specific
  artifact checksum in `config/host-tools.env`. Renovate must check these
  releases daily and open a reviewed PR; required architecture tests and the
  affected-workload E2E suite must pass before merge. Global changes run the
  full E2E suite. A host-root updater may consume only validated data from the
  deployed release and must never execute scripts from the mutable Git
  checkout. Fedora repository packages remain Fedora-managed.
- Onboard new applications and services from the latest stable upstream
  release available at the time of onboarding. Do not deliberately select an
  older, prerelease, nightly, or end-of-life release; any unavoidable
  exception must be documented with its reason and upgrade plan.
- Use explicit non-root container users whenever the image supports them. If
  the exact image requires UID 0, document the reason in
  `docs/rootless-images.md` and in the workload inventory; root inside a
  rootless container is an exception, not a default.
- Every container must retain the applicable hardening stanza:
  `NoNewPrivileges=true`, `DropCapability=all`, `ReadOnly=true`,
  `ReadOnlyTmpfs=true`, `PodmanArgs=--image-volume=ignore`, and
  `PidsLimit=1024`. Keep `LogDriver=journald`, `Restart=always`,
  `RestartSec=5s`, and `TimeoutStartSec=900` consistent with existing units.
  Use `RunInit=true` where the image is compatible.
- Add capabilities only when a demonstrated application requirement needs
  them. The current allowlist is `NET_BIND_SERVICE`, `CHOWN`,
  `DAC_OVERRIDE`, `FOWNER`, `SETGID`, and `SETUID`; justify every exception in
  the workload inventory.
- Keep SELinux enforcing. Normal containers use `container_t`. Reserve
  `container_device_t` and `AddDevice=` for narrowly scoped hardware access,
  keep `container_use_devices` off, and never use `spc_t`, disabled/nested
  labels, or an unconfined seccomp profile.
- Use named Podman volumes for writable persistent state. Give each volume a
  `VolumeName=homelab-...` and
  `Label=io.containers.systemd.application=<workload>`; use `:U` on writable
  mounts. Deployment-owned bind mounts are read-only and privately relabeled
  with `:ro,Z`.
- Keep secrets out of images, Git plaintext, command arguments, and ordinary
  environment values. Import them as Podman secrets from SOPS-rendered data.
- Do not expose a web UI with `PublishPort=`. Put the service on its workload
  edge network and add a Caddy reverse-proxy route. Direct published ports
  require a non-HTTP protocol or another explicitly reviewed host-integration
  need.

## Onboarding a new application or service

Complete every applicable item below in one change. Start by reviewing the
upstream image's user, data paths, startup command, health check, architecture,
required capabilities, ports, outbound dependencies, and upgrade/migration
behavior. Prefer the smallest number of containers and networks that preserve
the required isolation.

Select the latest stable upstream release before choosing the image tag and
digest. Verify the release against the upstream project, then pin that exact
version and digest in the Quadlet and any custom build inputs. Renovate keeps
the deployment current after onboarding, but it does not justify starting a
new workload on an older release.

### 1. Create the deployment units

For a new workload, create the following structure and add every service to
it. For a service added to an existing workload, use that workload's existing
directory and target.

```text
quadlet/applications/<workload>/<service>.container
quadlet/networks/<workload>.network
quadlet/volumes/<workload>-<purpose>.volume       # for persistent state
systemd/user/homelab-<workload>.target
```

Each container unit must have a unique `ContainerName`, the appropriate
`User=`, `Network=`, `PartOf=homelab-<workload>.target`, dependency ordering
with `After=`/`Requires=`, and the standard security and restart settings.
Use service DNS names on Podman networks instead of host addresses.
PostgreSQL and MariaDB units must be named `<service>-postgres.container`
and `<service>-mariadb.container`; `bin/migrate-databases` discovers only
those globs and will skip any other database filename.

If the application needs a locally built image, also create:

```text
images/<image>/Containerfile
quadlet/builds/<image>.build
```

Pin every build base image, keep build-time root use separate from runtime
root use, add the build unit to the workload manifest, and update
`bin/reconcile` if the new build requires an explicit restart path.

### 2. Register the workload everywhere

Update all of these inventories and activation paths:

- Add the workload to `manifests/applications.json`, including every generated
  service unit and every Podman secret consumed by those units.
- Keep `systemd/user/homelab-<workload>.target`'s `Wants=` list exactly in sync
  with the manifest. Add the target to `systemd/user/homelab.target` and the
  target list in `bin/status`.
- Add one entry to `tests/e2e-readiness.json` for every `ContainerName`, not
  merely every workload. Use `health`, `tcp`, or `running` as described below.
- Update any hard-coded counts, allowlists, topology rules, or runtime audit
  lists in `tests/static.sh` and `bin/security-audit` that intentionally
  describe the active deployment.

Container filenames, service unit names, manifest entries, target Wants, and
`ContainerName` values must remain unambiguous and consistent. Do not put
inactive experiments in the active manifest; preserve them under `incubator/`
with their own notes if they are not ready for deployment.

### 3. Design networks and exposure

Allocate unused deterministic `/24` ranges inside `10.200.0.0/16`. Every
network must use `Options=isolate=true`, have a workload label, and avoid
overlap with host, LAN, VPN, or other container routes.

- Use an `Internal=true` backend network for databases, caches, queues, and
  private service-to-service traffic.
- Create a separate `<workload>-edge.network` only for services that Caddy
  must reach. Caddy joins edge networks, never database/cache/MQTT backend
  networks.
- Add a dedicated egress network only when a component needs outbound access
  that should be isolated from the rest of the workload. Record the reason.
- Keep databases, caches, MQTT brokers, and workers off edge networks.
- Add no `Network=host` and no direct UI `PublishPort=`.

For a UI or HTTP API, update all applicable items:

1. Add a hostname route to `config/templates/caddy/Caddyfile` using the
   service DNS name and the shared `default-header`/compression policy.
2. Attach the Caddy container and the proxied service to the same edge
   network, while keeping the service's backend network separate.
3. Handle application-specific websocket, notification, upload-size, host,
   forwarded-header, or trusted-proxy requirements explicitly. Vaultwarden's
   notification routes and Supernote's forwarded headers are reference
   patterns.
4. Add the hostname to the DNS/hostname list in `README.md` and document any
   LAN-only or public exposure decision.

If the application has no UI, record `none` in the workload inventory. If it
needs a non-HTTP external protocol, add the smallest explicit `PublishPort=`
set, update `bin/bootstrap-host`/firewalld documentation and the static port
assertion, and explain why Caddy cannot provide that exposure. Syncthing's
TCP/UDP 22000 mapping is the current example.

### 4. Add state, configuration, and secrets

For every writable path, decide whether it is disposable cache or durable
application state. Durable state must have a named volume unit, a workload
label, a `:U` mount, and a backup/restore note. Update `docs/backups.md` or
`docs/restore-volume.md` when the service has ordering, seed-data, or
multi-volume restore requirements.

For rendered configuration or credentials:

- Add templates under `config/templates/<workload>/` and render them from
  `bin/render-config`. Keep the rendered tree below `%t/homelab`, mode `0700`
  at its parent, and use read-only `:ro,Z` mounts into containers.
- Add new supported site settings to `config/site.env` and the strict parser
  in `bin/lib.sh`; do not silently accept arbitrary environment keys.
- Add the secret schema to `secrets/secrets.example.yaml`, import each
  container secret in `bin/render-config`, and extend `bin/init-secrets` when
  fresh installation must prompt for or generate the value.
- Update the real E2E plaintext secret fixture and cleanup inventory in
  `tests/e2e.sh`. Encrypted deployment data is generated or edited through
  SOPS only; never commit a plaintext secret or an unencrypted test value in
  production configuration.

For seeded data, migration files, or downloaded assets, add the checked-in
checksum/metadata and update `bin/fetch-assets` when the source must be
retrieved during reconciliation. Supernote's checked SQL seed is the current
example. Ensure the data is mounted read-only when it is deployment-owned.

### 5. Add real E2E coverage

Every declared container needs a readiness entry:

- Prefer a native Quadlet `HealthCmd=` with suitable `HealthInterval=`,
  `HealthTimeout=`, `HealthRetries=`, `HealthStartPeriod=`, and
  `Notify=healthy` where supported. PostgreSQL, MariaDB, and Valkey show the
  preferred pattern.
- Use `tcp` only when a real listener is the meaningful readiness contract;
  specify the exact Podman network and container port in
  `tests/e2e-readiness.json`.
- Use `running` only when no meaningful health or TCP check exists, and record
  the reason in the workload inventory. It must never hide a known unhealthy
  service.

If the service needs hardware, credentials, an external dependency, or seed
data, add a test-only fixture under `tests/fixtures/`. Fixtures must themselves
run through Podman. Adapt `tests/e2e.sh` to build or inject the fixture and to
remove its resources during cleanup. Do not mock `podman` or `systemctl`, skip
the new container, or replace E2E with a shell-only check.

Run the focused checks first. Repeat `--workload` when a change affects more
than one workload:

```bash
./bin/e2e --container CONTAINER_NAME
./bin/e2e --workload WORKLOAD_NAME
./bin/e2e --workload WORKLOAD_NAME --workload OTHER_WORKLOAD_NAME
```

The selected run must start every declared container in the selected workload
and its declared dependencies, verify readiness, and keep those containers
running through the stability check. A global change must use `./bin/e2e`
which starts every declared container and passes the runtime security audit.
The CI workflow uses `bin/e2e-targets` to select this scope from the Git diff;
documentation-only changes do not start a Podman machine.

### 6. Finish validation and operational documentation

Before merging an onboarding change, run:

```bash
./bin/validate
./tests/static.sh
./tests/backup.sh
./bin/e2e --workload WORKLOAD_NAME
```

Run `./bin/e2e` as well when the change is global or when a complete local
deployment check is desired.

Also run ShellCheck when available, inspect `systemctl --user`/Quadlet
generator output, and check recent SELinux AVC denials after activation. Update
`README.md`, a workload-specific document, or the recovery guides when the
application adds a login/bootstrap step, external DNS or firewall requirement,
architecture exception, migration procedure, or special backup semantics.

Review image updates through Renovate; never enable automatic image updates.
For grouped services or custom build dependencies, update `renovate.json` so
the images and build inputs are reviewed together.

### Host-tool updates

Manually fetched host tools are deployment dependencies and must follow the
same reviewed update path as images:

- Keep release tags and all architecture-specific checksums in
  `config/host-tools.env`; derive URLs and filenames in the installer from a
  fixed upstream repository.
- Renovate checks daily and opens a non-automerged pull request. Require the
  host-tool tests for every supported architecture and the complete Podman E2E
  suite before merging to `main`.
- Installers must validate the checksum and package metadata before changing a
  host installation, reject downgrades, and leave the current version intact
  on failure.
- If root is required, install a fixed helper during trusted host bootstrap.
  The helper may parse deployed metadata but must not execute repository code
  as root. Document the timer, recovery behavior, and one-time rollout for
  existing hosts.

## Workload inventory

This is the compact record that must be updated whenever an application or
service is onboarded. The Quadlet units and policy documents remain the
authoritative detailed configuration.

| Workload | Runtime and dependency pattern | Networks / UI / external exposure | State, secrets, and special security notes |
| --- | --- | --- | --- |
| `caddy` | Custom build; reverse-proxy entrypoint | All active edge networks; `*.BASE_DOMAIN`; loopback `127.0.0.1:8443` only | Caddy user; Cloudflare and bookmarks secrets; `NET_BIND_SERVICE`; never joins backend networks |
| `forgejo` | Rootless Forgejo plus PostgreSQL | Backend plus Forgejo edge; `git` route | Rootless UIDs; Forgejo and PostgreSQL volumes; database secret |
| `homeassistant` | Home Assistant, Mosquitto, and Zigbee2MQTT | Backend plus Home Assistant edge; `home` and `home-zigbee` routes | Zigbee device fixture and `container_device_t` exception; D-Bus read-only bind; MQTT Podman secret plus `ZIGBEE2MQTT_CONFIG_*` GitOps env; writable Zigbee2MQTT data volume |
| `immich` | Rootless server, PostgreSQL, Valkey, and ML service | Backend plus server edge; dedicated ML egress; `photos` route | Multiple durable volumes; database secret; ML outbound isolation |
| `radicale` | Custom rootless image with rendered config | Internal Radicale network; `contacts` route; no Internet egress | Bcrypt htpasswd secret; custom build and rendered user/config files |
| `searxng` | Rootless SearXNG plus Valkey | Backend plus SearXNG edge; `search` route | Rendered secret-key settings and cache volume; Valkey remains backend-only |
| `supernote` | MariaDB, Valkey, notelib, and service | Internal backend plus internal service edge and internal notelib network; `supernote` route; no Internet egress | Seeded SQL asset; multiple durable volumes; amd64/QEMU exception; narrowly allowlisted `CHOWN`/`NET_BIND_SERVICE`; notelib network retains a historical `egress` name without a documented outbound dependency |
| `syncthing` | Rootless single service | Internal Syncthing network; `syncthing` UI route; TCP/UDP `22000` direct; no Internet egress | Durable data volume; direct protocol exposure is documented and firewalled; Internet discovery/relay and outbound peer sessions are unavailable |
| `vaultwarden` | Rootless single service | Internal Vaultwarden network; `vault` UI, websocket, and notification routes; no Internet egress | Durable data volume; admin token secret; websocket routing must remain tested |

Inactive bundles under `incubator/` are useful reference implementations but
are not active workload inventory entries. AnythingLLM demonstrates a simple
rootless service with one isolated network and multiple volumes. Docs MCP
demonstrates a multi-container workload with shared volumes, secrets,
dependency ordering, a native health check, and multiple Caddy routes. Before
moving either bundle into the active deployment, apply this entire checklist
and add a new inventory record.

## Useful references

- `README.md` — host prerequisites, GitOps operation, external DNS, security
  model, backup inventory, and recovery procedures.
- `docs/rootless-images.md` — explicit non-root image users and documented
  exceptions.
- `manifests/applications.json` — workload/unit/secret registration.
- `tests/static.sh` — repository topology and security invariants.
- `tests/e2e-readiness.json` and `tests/e2e.sh` — real Podman readiness and
  fixture conventions.
- `bin/render-config`, `bin/reconcile`, `bin/migrate-databases`, and `bin/security-audit` — secret
  rendering, activation, automated PostgreSQL/MariaDB major migrations, and runtime enforcement.

## GitHub Actions

- When creating or updating GitHub Actions workflows, always use the latest stable release of each action.
- Pin every `uses:` reference to the action's full commit SHA. Do not use mutable tags or branches.
- Put the human-readable action version immediately after the pinned SHA as a comment.
- Whenever the action version changes, update both the version comment and the pinned commit SHA together.

Example:

```yaml
uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```
