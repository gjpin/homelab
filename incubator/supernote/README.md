# Supernote Private Cloud

This is an inactive preserved bundle. It is not loaded by the active homelab
deployment.

## Preserved material

- `quadlet/supernote-*.container`: the MariaDB, notelib, service, and Valkey container definitions.
- `quadlet/supernote*.network`: the backend, Caddy edge, and notelib egress network definitions.
- `quadlet/supernote-*.volume`: the 10 persistent storage volume definitions.
- `systemd/homelab-supernote.target`: the original application systemd target.
- `manifest.json`: the original application unit and secret inventory.
- `secrets/secrets.example.yaml`: the original secret schema.
- `caddy/routes.Caddyfile`: the original `supernote` reverse-proxy route snippet.
- `assets/supernotedb.sql` and `assets/supernotedb.sql.sha256`: the initial database bootstrap SQL and sha256 checksum.
- `config/valkey.conf`: the Valkey runtime configuration template.

## Execution and security notes

- **Users and volumes**:
  - `supernote-mariadb` runs as `mysql:mysql` with `:U` alignment on `supernote-mariadb.volume`.
  - `supernote-valkey` runs as `1000:1000` with `:U` alignment on `supernote-valkey.volume`.
  - `supernote-notelib` and `supernote-service` have no upstream non-root contract and run as UID 0 inside their rootless container boundaries.
- **Architecture**:
  - Upstream `docker.io/supernote/notelib` and `docker.io/supernote/supernote-service` images are published for amd64 only. The Quadlets set `PodmanArgs=--arch=amd64 --image-volume=ignore` so they run under QEMU emulation on ARM64 hosts.
- **Capabilities**:
  - `supernote-service` requests allowlisted `CHOWN` and `NET_BIND_SERVICE` capabilities for internal entrypoint and port binding operations.
- **Networks**:
  - `supernote.network` (internal backend), `supernote-edge.network` (internal Caddy edge), and `supernote-notelib-egress.network` (isolated egress network) all specify `Internal=true` and `Options=isolate=true`.
- **State and secrets**:
  - Consumes `supernote-database-root-password`, `supernote-database-user-password`, and `supernote-valkey-password` Podman secrets.
  - Existing named persistent volumes (`homelab-supernote-*`) on deployment hosts are preserved during decommissioning and not deleted.
