#!/usr/bin/bash

# TODO:
# Review https://www.seanh.cc/2022/04/03/restic/

# Install restic
sudo apt install -y restic

# Create log directory
sudo mkdir -p /var/log/restic
sudo chown root:root /var/log/restic
sudo chmod 755 /var/log/restic

# Create backup script
sudo tee /usr/local/bin/restic-backup.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# CONFIGURATION ------------------------------------------
BACKUP_PATH="/data/containers"
LOG_DIR="/var/log/restic"
LOG_FILE="${LOG_DIR}/restic-backup-$(date +%F).log"
# ---------------------------------------------------------

mkdir -p "$LOG_DIR"

log() {
    echo "$(date --iso-8601=seconds) $*" | tee -a "$LOG_FILE"
}

log "==================== NEW BACKUP RUN ===================="

log "Starting backup script"

# Get running containers
RUNNING_CONTAINERS=$(docker ps -q)

if [[ -n "$RUNNING_CONTAINERS" ]]; then
    log "Pausing containers: $RUNNING_CONTAINERS"
    docker pause $RUNNING_CONTAINERS | tee -a "$LOG_FILE"
else
    log "No containers to pause."
fi

# Ensure containers unpause even if backup fails
cleanup() {
    if [[ -n "$RUNNING_CONTAINERS" ]]; then
        log "Unpausing containers: $RUNNING_CONTAINERS"
        docker unpause $RUNNING_CONTAINERS | tee -a "$LOG_FILE"
    fi
    log "Backup script finished."
    log "========================================================"
}
trap cleanup EXIT

log "Running restic backup..."
restic -r "$RESTIC_REPO" backup "$BACKUP_PATH" 2>&1 | tee -a "$LOG_FILE"

log "Running restic forget + prune..."
restic -r "$RESTIC_REPO" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune 2>&1 | tee -a "$LOG_FILE"

log "Backup completed successfully."
EOF

sudo chmod +x /usr/local/bin/restic-backup.sh

# Create systemd service
sudo tee /etc/systemd/system/restic-backup.service << 'EOF'
[Unit]
Description=Restic backup of /data/containers
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/restic/env

# Send stdout/stderr to journald
StandardOutput=journal
StandardError=journal

# Run the script (which also handles its own log file)
ExecStart=/usr/local/bin/restic-backup.sh

# Lower priority so it doesn't disturb the system
Nice=10
IOSchedulingClass=idle

# Prevent overlapping runs
RuntimeMaxSec=6h
EOF

# Create systemd service timer
sudo tee /etc/systemd/system/restic-backup.timer << 'EOF'
[Unit]
Description=Daily Restic Backup Timer

[Timer]
OnCalendar=*-*-* 04:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer