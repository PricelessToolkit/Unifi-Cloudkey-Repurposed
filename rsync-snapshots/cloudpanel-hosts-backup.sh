# This script is used to back up CloudPanel-hosted sites from a VPS to a local machine.
#
# It is intended to work together with a custom backup job created inside CloudPanel.
# In CloudPanel, you should create a custom rsync backup job that stores backup files
# inside each site user directory, for example in:
#
#   /home/<site-user>/backups
#
# This script connects to the VPS over SSH using an SSH key, finds all CloudPanel site
# backup folders, and downloads them to the local server. It also downloads the matching
# htdocs folder from the same parent directory, so both the backup files and website files
# are copied locally.
#
# The local folder structure is organized by the parent directory name, for example:
#
#   /home/webhost/backups   ->   ~/vps-backups/webhost/backups
#   /home/webhost/htdocs    ->   ~/vps-backups/webhost/htdocs
#
# Excluded system folders:
#   /home/mysql
#   /home/clp
#   /home/ubuntu
#
# The rsync command uses --delete, which means the local copy is kept in sync with the VPS.
# If a file is removed from the remote backup or htdocs folder, it will also be removed
# from the local copy during the next run.
#
# In short:
# 1. Create a custom rsync backup job in CloudPanel that writes site backups locally.
# 2. Run this script from your local server or desktop.
# 3. The script downloads all detected CloudPanel site backups and htdocs folders
#    from the VPS to your local backup destination.


#!/usr/bin/env bash
set -euo pipefail

REMOTE_USER="root"
REMOTE_HOST="YOUR_CloudPanel_IP"
SSH_KEY="/home/LOCAL_USERNAME/.ssh/id_ed25519"
LOCAL_DEST="$HOME/vps-backups"

EXCLUDES=("mysql" "clp" "ubuntu")

mkdir -p "$LOCAL_DEST"

SSH_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
)

EXCLUDE_EXPR=""
for name in "${EXCLUDES[@]}"; do
  EXCLUDE_EXPR="$EXCLUDE_EXPR ! -path /home/$name/backups"
done

REMOTE_FIND_CMD="find /home -mindepth 2 -maxdepth 2 -type d -name backups $EXCLUDE_EXPR | sort"

mapfile -t BACKUP_DIRS < <(
  ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "$REMOTE_FIND_CMD"
)

if [ ${#BACKUP_DIRS[@]} -eq 0 ]; then
  echo "No backup folders found."
  exit 0
fi

for remote_backup_dir in "${BACKUP_DIRS[@]}"; do
  parent_dir="$(dirname "$remote_backup_dir")"
  parent_name="$(basename "$parent_dir")"
  local_parent_dir="$LOCAL_DEST/$parent_name"

  mkdir -p "$local_parent_dir"

  echo "Syncing $remote_backup_dir -> $local_parent_dir/backups/"
  mkdir -p "$local_parent_dir/backups"
  rsync -avz --delete --progress \
    -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
    "${REMOTE_USER}@${REMOTE_HOST}:${remote_backup_dir}/" \
    "$local_parent_dir/backups/"

  echo "Syncing $parent_dir/htdocs -> $local_parent_dir/htdocs/"
  mkdir -p "$local_parent_dir/htdocs"
  rsync -avz --delete --progress \
    -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
    "${REMOTE_USER}@${REMOTE_HOST}:${parent_dir}/htdocs/" \
    "$local_parent_dir/htdocs/" || true
done

echo "Done. Saved in $LOCAL_DEST"
