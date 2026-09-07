# Agent instructions

This repository is a rootful Docker Compose deployment on Debian.
A container or workload change is incomplete until it has real Docker
E2E coverage and passes the repository's security and topology checks.

Keep this file current when onboarding an application or service.

## Non-negotiable deployment rules

- Run production workloads with rootful Docker CE and Compose v2. Do not add
  privileged containers. Do not mount the production Docker socket into CI.
- Pin every upstream container image and every Containerfile base image by
  immutable `@sha256:` digest. Do not use `:latest`, floating tags, or auto
  updates.
- Pin host-tool releases and architecture checksums in `config/host-tools.env`
  (age, restic, sops, forgejo-runner). Renovate opens reviewed PRs. The host
  timer may consume only the copied installers under `/usr/local/lib/homelab/`.
- Onboard from the latest stable upstream release. Document any exception.
- Use explicit non-root `user:` when the image supports starting that way on an
  empty named volume. Official Postgres and Redis entrypoints start as root and
  drop privileges; do not set `user:` on those services.
- Every compose service keeps `restart: always`, `read_only: true`,
  `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]`, `pids_limit: 1024`,
  `init: true` (false only for Home Assistant s6), `tmpfs: [/tmp]`, and
  `logging.driver: journald`. Do not set `apparmor=unconfined`.
- Add capabilities only when required. The allowlist is `NET_BIND_SERVICE`,
  `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`, and `SETPCAP`.
- AppArmor must be enabled. Containers use Docker's generated `docker-default`
  profile. Bootstrap installs `apparmor` from apt.
- Use named Docker volumes for writable state (`homelab-...`, label
  `homelab.application=<workload>`). Deployment-owned bind mounts are read-only.
- Keep secrets out of images, Git plaintext, and command arguments. Import them
  from SOPS into `~/.local/state/homelab/rendered`.
- Do not expose a web UI except through Caddy. Caddy publishes host `443:443`.
  Syncthing may publish TCP/UDP 22000. No other `ports:`.

## Onboarding

```text
compose/<workload>/compose.yaml
systemd/system/homelab.service   # already starts every manifest app
```

Register the workload in `manifests/applications.json` and
`manifests/networks.json`. Add a Caddy route when the app has HTTP. Add
readiness in `tests/e2e-readiness.json` for every `container_name`.

Use `internal: true` named networks for databases, caches, and no-egress apps.
Give Caddy a separate edge network, or attach it to the no-egress app network.
Never attach Caddy to backend DB/cache/MQTT networks. Let Docker assign subnets.

Render configuration from `config/templates/<workload>/` via `bin/render-config`.

## Forgejo Actions

The runner is an arbitrary-code-execution workload. It runs as locked
`forgejo-runner` with rootless Docker, isolated storage, nftables egress, and
no access to production Docker, volumes, secrets, or the homelab account.

## Workload inventory

| Workload | Pattern | Networks / UI | Notes |
| --- | --- | --- | --- |
| `caddy` | Custom build | All edge / no-egress app nets; `*.BASE_DOMAIN`; host 443 | Cloudflare and bookmarks secrets; `NET_BIND_SERVICE` |
| `forgejo` | App + Postgres | Backend + edge; `git` | Database secret |
| `homeassistant` | HA, Mosquitto, Zigbee2MQTT | Backend + edge; `home`, `home-zigbee` | Zigbee device + D-Bus; MQTT secret; HA `init: false` |
| `immich` | Server, Postgres, Redis, ML | Backend + server edge + ML egress; `photos` | Redis replaces Valkey; database secret |
| `radicale` | Official image | Internal net; `contacts` | `ghcr.io/kozea/radicale`; uid 1000; htpasswd in rendered files |
| `searxng` | App + Redis | Backend + edge; `search` | Redis URL in settings |
| `syncthing` | Single service | Internal net; `syncthing` UI; TCP/UDP 22000 | Durable data volume |
| `vaultwarden` | Single service | Internal net; `vault` | Admin token secret |
