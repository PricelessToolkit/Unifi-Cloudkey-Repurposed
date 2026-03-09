#!/usr/bin/env bash
set -Eeuo pipefail

# CONFIG

# Name shown in Telegram error message
JOB_NAME="MY CLONE JOB"

# Local source directory
# With trailing slash:  /data/source/  -> copies contents of source
# Without trailing slash: /data/source -> copies the source directory itself
LOCAL_PATH="/path/to/local/source/"

# Remote SSH username
REMOTE_USER="user"

# Remote server IP address or hostname
REMOTE_HOST="192.168.1.10"

# Remote SSH port
REMOTE_PORT="22"

# Remote destination directory
REMOTE_PATH="/path/to/remote/destination/"

# TELEGRAM

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

# Check that local source directory exists before running rsync
if [[ ! -d "${LOCAL_PATH}" ]]; then
  echo "Local path does not exist: ${LOCAL_PATH}"
  exit 1
fi

# Clone local directory to remote server using rsync over SSH
# -a   archive mode
# -H   preserve hard links
# -A   preserve ACLs
# -X   preserve extended attributes
# --numeric-ids preserve numeric user/group IDs
# --delete remove files on remote that no longer exist locally
# --human-readable show readable sizes
# --info=progress2,stats2 show overall progress and final statistics

rsync \
  -aHAX \
  --numeric-ids \
  --delete \
  --human-readable \
  --info=progress2,stats2 \
  -e "ssh -p ${REMOTE_PORT}" \
  "${LOCAL_PATH}" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
