# Rootless image policy

This deployment already uses rootless Podman: every application unit is a
systemd user service owned by the locked `homelab` account. In this document,
“rootless image” also means that the process inside the container is explicitly
started as a non-zero UID. Those are separate protections, so an image that
must start as UID 0 below is still isolated from host root by rootless Podman.

The non-root settings below are part of the Quadlet units rather than inferred
from mutable image defaults. `:U` is used on writable named volumes so Podman
aligns their ownership with the selected container UID. This may change the
ownership metadata of an existing volume on the first activation after this
change; take a backup before deploying to a host with existing data.

## Explicit non-root services

| Service | Container user | Image or upstream basis |
| --- | ---: | --- |
| Caddy | `caddy:caddy` | Final custom image creates a fixed UID/GID 1000 user; the build stage still needs build tooling as root. |
| Forgejo | `1000:1000` | Forgejo’s documented `16.0.3-rootless` image; its data mount is `/var/lib/gitea` and its embedded SSH port is 2222. This deployment does not publish Forgejo SSH. |
| Forgejo PostgreSQL | `postgres:postgres` | The official PostgreSQL image supports a baked-in non-root `postgres` user; the volume is aligned before the entrypoint initializes it. |
| Mosquitto | `1883:1883` | Eclipse Mosquitto documents this UID/GID for the broker. |
| Zigbee2MQTT | `1000:1000` | The image entrypoint only execs the application; the data volume and rendered files are made usable by the explicit non-root user. `GroupAdd=keep-groups` preserves coordinator access through the host `dialout` group. Bootstrap installs a udev rule that keeps the coordinator at `0660` `dialout` and removes `uaccess`, so an SSH seat cannot take exclusive ownership after the device is released. |
| Immich server, ML, PostgreSQL, and Valkey | `1000:1000` | Immich publishes a rootless compose configuration using this user for all four services. The cache uses the official Valkey image from that configuration. |
| Radicale | `radicale:radicale` | Local image declares this user. |
| SearXNG | `977:977` | The image’s `searxng` account is UID 977; matching it avoids the image’s cache ownership mismatch. `FORCE_OWNERSHIP=false` is safe here because the volume is aligned with `:U`. |
| Supernote MariaDB | `mysql:mysql` | The official MariaDB image contains the `mysql` user and its non-root entrypoint path; the data volume is aligned with `:U`. |
| Supernote Valkey | `1000:1000` | Valkey is run directly as a non-root service user; its writable volume is aligned with `:U`. |
| Syncthing | `1000:1000` | Syncthing documents UID/GID 1000 as its container default. |
| Vaultwarden | `1000:1000` | Vaultwarden documents non-root operation with an explicit UID/GID; its Rocket listener is moved to 8080. |

## Exceptions

These services intentionally do not set `User=` because no compatible
upstream rootless image or documented non-root startup path was available for
the exact image and persistent-data contract used here:

- `homeassistant`: the upstream image relies on its root s6 initialization
  model and also integrates with host D-Bus; a non-root variant is not
  published for this image. The unit sets `RunInit=false` because s6-overlay must
  be PID 1; injecting catatonit makes the entrypoint exit 100.
- `supernote-notelib` and `supernote-service`: the vendor images have no
  rootless variants or documented non-root contract, and their startup/data
  layout is application-specific.

The exceptions are root inside their containers only. They still run under
the rootless `homelab` Podman service, with dropped capabilities, read-only
root filesystems, and `NoNewPrivileges=true`.

The upstream references used for this policy are [Forgejo’s rootless image
instructions](https://forgejo.org/docs/v16.0/admin/installation/docker/#using-rootless-image),
Immich’s [rootless compose configuration](https://github.com/immich-app/immich/blob/main/docker/docker-compose.rootless.yml),
[PostgreSQL’s arbitrary-user notes](https://github.com/docker-library/docs/blob/master/postgres/README.md#arbitrary-user-notes),
[MariaDB’s container entrypoint](https://github.com/MariaDB/mariadb-docker/blob/master/docker-entrypoint.sh),
Vaultwarden’s [non-root hardening guidance](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide),
Syncthing’s [Docker user documentation](https://github.com/syncthing/syncthing/blob/main/README-Docker.md),
and the [Mosquitto container documentation](https://github.com/eclipse-mosquitto/mosquitto/blob/master/docker/generic/README.md).
The SearXNG UID choice follows the documented [cache ownership issue and
UID-977 workaround](https://github.com/searxng/searxng/issues/6044).

Build and validation containers are separate from deployed services. The Caddy
builder, Radicale package-install stage, and Fedora CI validation container
need root inside their temporary build/test environments to install packages;
their resulting runtime image or deployment service is non-root where
supported.
