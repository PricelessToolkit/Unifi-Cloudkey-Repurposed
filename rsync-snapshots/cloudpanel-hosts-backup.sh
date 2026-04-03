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
