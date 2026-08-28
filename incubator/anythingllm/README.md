# AnythingLLM

This is an inactive preserved bundle. It is not loaded by the active homelab
deployment.

## Preserved material

- `quadlet/anythingllm.container`: the AnythingLLM container definition.
- `quadlet/anythingllm.network`: the isolated network definition.
- `quadlet/anythingllm-data.volume`: the persistent storage definition.
- `systemd/homelab-anythingllm.target`: the original application target.
- `manifest.json`: the original application unit inventory.
- `caddy/routes.Caddyfile`: the original `chat` reverse-proxy route.

AnythingLLM also uses the host-managed state file
`~/.local/state/homelab/anythingllm/.env`. The existing host state and named
volume are intentionally not removed by this reorganization.

The container runs as `anythingllm:anythingllm`. Its writable `.env` is kept
private by the mode `0700` parent state directory while the file itself is
mode `0666` for the mapped rootless user.
