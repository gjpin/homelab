# Restore one older volume on the existing host

Create a safety snapshot, then replace one named Docker volume from an older
restic snapshot. Related database and file volumes must come from the same
snapshot.

```bash
sudo env HOME=/home/homelab /home/homelab/current/bin/backup --tag pre-restore
snapshot=OLDER_SNAPSHOT_ID
volume=homelab-vaultwarden-data
app=vaultwarden
```

Stop the owning compose project, recreate the volume, restore into its
mountpoint, then start the project:

```bash
export HOME=/home/homelab HOMELAB_STATE_DIR=/home/homelab/.local/state/homelab
cd /home/homelab/current
homelab_compose() { ./bin/lib.sh >/dev/null; }
docker compose --project-name "homelab-$app" --file "compose/$app/compose.yaml" stop
docker volume rm "$volume"
docker volume create --label "homelab.application=$app" "$volume"
mountpoint=$(docker volume inspect --format '{{.Mountpoint}}' "$volume")
src=$(awk -F'\t' -v v="$volume" '$1==v{print $2}' \
  ~/.local/state/homelab/backup-metadata/volume-map.tsv)
./bin/restic restore "$snapshot:$src" --target "$mountpoint"
docker compose --project-name "homelab-$app" --file "compose/$app/compose.yaml" up -d
```
