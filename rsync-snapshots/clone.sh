#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# UNIVERSAL RSYNC CLONE SCRIPT
#
# What this does:
# - Syncs a local directory to a remote server using rsync over SSH
# - Deletes files on the remote side that no longer exist locally
# - Sends a Telegram message if the job fails
#
# SSH KEY SETUP
#
# 1) Generate a key on the source machine:
#    ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_backup
#
#    For cron usage, leave the passphrase empty.
#
# 2) Copy the public key to the remote server:
#    ssh-copy-id -i ~/.ssh/id_ed25519_backup.pub -p 22 user@remote-host
#
# 3) Test login with the key:
#    ssh -i ~/.ssh/id_ed25519_backup -p 22 user@remote-host
#
# 4) If that works without a password, this script can use the key.
#
# TRAILING SLASH BEHAVIOR
#
# - LOCAL_PATH="/data/source/"
#   Copies the CONTENTS of /data/source/ into the remote destination
#
# - LOCAL_PATH="/data/source"
#   Copies the source directory itself into the remote destination
#
# EXAMPLE CRON
#
# Run every day at 02:00 and 14:00:
# 0 2,14 * * * /root/clone-job.sh >> /var/log/clone-job.log 2>&1
#
###############################################################################

# Name shown in Telegram error message
JOB_NAME="MY CLONE JOB"

# Local source directory
LOCAL_PATH="/path/to/local/source/"

# Remote SSH settings
REMOTE_USER="user"
REMOTE_HOST="example.com"
REMOTE_PORT="22"

# SSH private key used for login
SSH_KEY="/root/.ssh/id_ed25519_backup"

# Remote destination directory
REMOTE_PATH="/path/to/remote/destination/"

# Optional extra rsync options
# Examples:
# RSYNC_EXTRA_OPTS=(--chown=user:group --chmod=D2775,F664)
# RSYNC_EXTRA_OPTS=(--numeric-ids)
RSYNC_EXTRA_OPTS=()

# Telegram bot token from BotFather
TELEGRAM_BOT_TOKEN="123456789:YOUR_BOT_TOKEN"

# Telegram chat ID where error message will be sent
TELEGRAM_CHAT_ID="123456789"

send_telegram() {
  local text="$1"

  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    >/dev/null 2>&1 || true
}

on_error() {
  local exit_code="$?"
  local line_no="$1"

  send_telegram "${JOB_NAME} FAILED
Host: $(hostname)
Line: ${line_no}
Exit code: ${exit_code}
Local: ${LOCAL_PATH}
Remote: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"

  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# Check local source exists
if [[ ! -e "${LOCAL_PATH}" ]]; then
  echo "Local path does not exist: ${LOCAL_PATH}"
  exit 1
fi

# Check SSH private key exists
if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key does not exist: ${SSH_KEY}"
  exit 1
fi

# Run rsync
#
# -a   archive mode
# -H   preserve hard links
# -A   preserve ACLs
# -X   preserve extended attributes
# --delete remove files on remote that no longer exist locally
# --human-readable show readable sizes
# --info=progress2,stats2 show overall progress and final statistics

rsync \
  -aHAX \
  --delete \
  --human-readable \
  --info=progress2,stats2 \
  "${RSYNC_EXTRA_OPTS[@]}" \
  -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT}" \
  "${LOCAL_PATH}" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
