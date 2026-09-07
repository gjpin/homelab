# Host migration and restore

For the one-time move from Fedora Quadlets to Debian Docker, use
[quadlet-to-docker.md](quadlet-to-docker.md).

For a later Docker-to-Docker replacement host:

1. On the source, `bin/backup --tag pre-migration --leave-stopped-on-success`.
2. Bootstrap Debian from this branch with `--host-age-key` and
   `--defer-forgejo-runner`.
3. Create the named volumes and restore each mountpoint from the snapshot's
   `volume-map.tsv`.
4. Start `homelab.service`, verify UIs, take `post-migration` backup.
5. Enable the Forgejo runner after DNS cutover.

Do not run two hosts with the same Forgejo runner UUID at once.
