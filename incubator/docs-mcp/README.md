# Docs MCP Server

This is an inactive preserved bundle. It is not loaded by the active homelab
deployment.

## Preserved material

- `quadlet/docs-mcp-*.container`: the worker, MCP server, and web services.
- `quadlet/docs-mcp.network`: the isolated network definition.
- `quadlet/docs-mcp-*.volume`: the persistent storage definitions.
- `systemd/homelab-docs-mcp.target`: the original application target.
- `manifest.json`: the original application unit and secret inventory.
- `secrets/secrets.example.yaml`: the original secret schema.
- `renovate.json`: the original grouped image-update rule.
- `caddy/routes.Caddyfile`: the original web, worker, and MCP reverse-proxy routes.

The bundle uses the `docs-mcp-openai-api-key` and optional
`docs-mcp-posthog-api-key` Podman secrets. Its existing named volumes are
intentionally not removed by this reorganization.

The worker, MCP server, and web containers run as `node:node`.
