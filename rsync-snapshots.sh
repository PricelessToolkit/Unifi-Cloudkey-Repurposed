#!/usr/bin/env bash
# rsync-snapshots.sh
# Snapshot backups over SSH using rsync + hard-linking (--link-dest), with:
# - remote snapshots named YYYY-MM-DD_HHMM
# - tmp/incomplete snapshots created on the SAME remote volume (/volume1, not eMMC)
# - keep last N snapshots
# - Telegram notify on failure (optionally on success)
# - Safety guard: require specific paths exist under LOCAL_BASE_DIR before running
# - Configurable excludes: extensions, directory names, extra patterns, and/or an excludes file
#
# Requirements (local): rsync, ssh, curl (only if you want Telegram)
# Requirements (remote): rsync, coreutils (mkdir, mv, ln, rm, ls, sort, readlink)

set -u
IFS=$'\n\t'

###############
# CONFIG START
###############

# Local source base directory (the whole tree under this will be backed up)
LOCAL_BASE_DIR="/data"   # <-- CHANGE THIS

# Safety guard: require these paths to exist under LOCAL_BASE_DIR before running.
# Space-separated, relative to LOCAL_BASE_DIR.
# Examples: "photos documents projects" or "important.db photos/2024"
# Set empty to disable.
REQUIRED_PATHS="photos documents"  # <-- CHANGE OR SET TO ""

# Remote SSH target
REMOTE_USER="root"
REMOTE_HOST="uckg2plus.lab.lan"
REMOTE_PORT="22"

# Remote base directory where snapshots/ will live (on your HDD volume)
REMOTE_BASE_DIR="/volume1/backup/rsync"
REMOTE_SNAP_DIR="${REMOTE_BASE_DIR}/snapshots"

# Retention: keep last N finished snapshots
SNAPSHOT_KEEP="10"

# Telegram notifications (optional)
TELEGRAM_NOTIFY_ON_FAILURE="1"   # 1 = yes, 0 = no
TELEGRAM_NOTIFY_ON_SUCCESS="0"   # 1 = yes, 0 = no (default off)
TELEGRAM_BOT_TOKEN=""            # e.g. "123456:ABC-DEF..."  (leave empty to disable)
TELEGRAM_CHAT_ID=""              # e.g. "-1001234567890" or "123456789" (leave empty to disable)

# --------------------------
# EXCLUDES (all optional)
# --------------------------

# Extensions to exclude anywhere (space-separated, with or without leading dot)
# Example: "mp4 mp3 iso"
EXCLUDE_EXTENSIONS="mp4 mp3"

# Directory names to exclude anywhere in the tree (names only, space-separated)
# Example: "pictures trash .Trash-1000 .Trashes @eaDir"
EXCLUDE_DIRNAMES="pictures trash"

# Extra rsync exclude patterns (newline-separated; supports rsync pattern syntax)
# Examples:
# EXCLUDE_PATTERNS=$'*.tmp\ncache/\nDownloads/\n**/.DS_Store'
EXCLUDE_PATTERNS=""

# Optional excludes file (one pattern per line). Leave empty to disable.
EXCLUDE_FILE=""

# SSH keepalive (helps stability; not a retry loop)
SSH_SERVER_ALIVE_INTERVAL="30"
SSH_SERVER_ALIVE_COUNT_MAX="6"

#############
# CONFIG END
#############

err() { echo "ERROR: $*" >&2; }

telegram_send() {
  local msg="$1"
  [[ "${TELEGRAM_BOT_TOKEN}" == "" || "${TELEGRAM_CHAT_ID}" == "" ]] && return 0
  command -v curl >/dev/null 2>&1 || return 0

  # Best-effort: don't fail the backup if Telegram fails.
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    -d "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }
}

need_cmd rsync
need_cmd ssh

# Build SSH command (as an array)
SSH_CMD=(
  ssh -p "${REMOTE_PORT}"
  -o BatchMode=yes
  -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL}"
  -o ServerAliveCountMax="${SSH_SERVER_ALIVE_COUNT_MAX}"
)

REMOTE="${REMOTE_USER}@${REMOTE_HOST}"

# Snapshot name (local machine time)
SNAP="$(date +%F_%H%M)"
TMP_NAME=".incomplete-${SNAP}"
TMP_REMOTE="${REMOTE_SNAP_DIR}/${TMP_NAME}"
FINAL_REMOTE="${REMOTE_SNAP_DIR}/${SNAP}"
LATEST_REMOTE="${REMOTE_SNAP_DIR}/latest"

############################################
# SAFETY CHECKS (before touching the remote)
############################################

# 1) Ensure source exists
if [[ ! -d "${LOCAL_BASE_DIR}" ]]; then
  err "LOCAL_BASE_DIR does not exist: ${LOCAL_BASE_DIR}"
  exit 1
fi

# 2) Safety guard: require specific folders/files exist
if [[ -n "${REQUIRED_PATHS}" ]]; then
  for p in ${REQUIRED_PATHS}; do
    if [[ ! -e "${LOCAL_BASE_DIR%/}/$p" ]]; then
      err "Required path missing: ${LOCAL_BASE_DIR%/}/$p. Refusing to run."
      [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]] && telegram_send "Backup FAILED (safety guard) on ${REMOTE_HOST}
Missing required path: ${LOCAL_BASE_DIR%/}/$p
Refusing to run."
      exit 1
    fi
  done
fi

########################
# REMOTE DIR PREPARATION
########################

# Ensure remote directories exist (on /volume1)
"${SSH_CMD[@]}" "${REMOTE}" "mkdir -p '${REMOTE_SNAP_DIR}'" || {
  err "Cannot create or access remote snapshot dir: ${REMOTE_SNAP_DIR}"
  [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]] && telegram_send "Backup FAILED: cannot access remote dir ${REMOTE_SNAP_DIR} on ${REMOTE_HOST}"
  exit 1
}

# Create remote tmp/incomplete directory (on /volume1)
"${SSH_CMD[@]}" "${REMOTE}" "rm -rf '${TMP_REMOTE}' && mkdir -p '${TMP_REMOTE}'" || {
  err "Cannot create remote tmp dir: ${TMP_REMOTE}"
  [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]] && telegram_send "Backup FAILED: cannot create tmp snapshot ${TMP_NAME} on ${REMOTE_HOST}"
  exit 1
}

# Determine if latest is valid (exists and points to an existing directory)
USE_LINK_DEST="0"
if "${SSH_CMD[@]}" "${REMOTE}" "test -L '${LATEST_REMOTE}' && test -d '${REMOTE_SNAP_DIR}/'\"\$(readlink '${LATEST_REMOTE}')\""; then
  USE_LINK_DEST="1"
fi

################
# RSYNC OPTIONS
################

RSYNC_OPTS=(-aH --numeric-ids --delete --delete-delay --partial --partial-dir=".rsync-partial" --stats)

# Add extension-based excludes
if [[ -n "${EXCLUDE_EXTENSIONS}" ]]; then
  for ext in ${EXCLUDE_EXTENSIONS}; do
    ext="${ext#.}"                    # strip leading dot if provided
    [[ -n "${ext}" ]] && RSYNC_OPTS+=(--exclude="*.${ext}")
  done
fi

# Add directory-name excludes (match directories anywhere)
if [[ -n "${EXCLUDE_DIRNAMES}" ]]; then
  for d in ${EXCLUDE_DIRNAMES}; do
    [[ -z "${d}" ]] && continue
    # Exclude any directory with that name anywhere, and everything under it
    RSYNC_OPTS+=(--exclude="/**/${d}/**")
    RSYNC_OPTS+=(--exclude="/**/${d}/")
  done
fi

# Add any custom patterns (newline-separated)
if [[ -n "${EXCLUDE_PATTERNS}" ]]; then
  while IFS= read -r pat; do
    [[ -z "${pat}" ]] && continue
    RSYNC_OPTS+=(--exclude="${pat}")
  done <<< "${EXCLUDE_PATTERNS}"
fi

# Add excludes file if configured
if [[ "${EXCLUDE_FILE}" != "" ]]; then
  if [[ ! -f "${EXCLUDE_FILE}" ]]; then
    err "EXCLUDE_FILE is set but does not exist: ${EXCLUDE_FILE}"
    exit 1
  fi
  RSYNC_OPTS+=(--exclude-from="${EXCLUDE_FILE}")
fi

# Add link-dest when available (relative to destination dir on remote)
if [[ "${USE_LINK_DEST}" == "1" ]]; then
  RSYNC_OPTS+=(--link-dest="../latest")
fi

# Source MUST end with / to copy contents into destination dir (not nest the base directory itself)
SRC="${LOCAL_BASE_DIR%/}/"
DEST="${REMOTE}:${TMP_REMOTE}/"

#############
# RUN RSYNC
#############

set +e
rsync "${RSYNC_OPTS[@]}" -e "${SSH_CMD[*]}" "${SRC}" "${DEST}"
RSYNC_EXIT=$?
set -e

if [[ "${RSYNC_EXIT}" -ne 0 ]]; then
  err "rsync failed with exit code ${RSYNC_EXIT}"
  if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
    telegram_send "Backup FAILED on ${REMOTE_HOST}
Snapshot: ${SNAP}
Exit code: ${RSYNC_EXIT}
Tmp: ${TMP_NAME}
Note: .incomplete snapshot left in place."
  fi
  exit "${RSYNC_EXIT}"
fi

#########################
# FINALIZE + UPDATE LATEST
#########################

"${SSH_CMD[@]}" "${REMOTE}" "
  set -e
  mv '${TMP_REMOTE}' '${FINAL_REMOTE}'
  ln -sfn '${SNAP}' '${LATEST_REMOTE}'
" || {
  err "Finalize failed (mv/ln) on remote"
  [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]] && telegram_send "Backup FAILED on ${REMOTE_HOST}
Snapshot: ${SNAP}
Finalize step failed (mv/ln)."
  exit 1
}

###################
# RETENTION CLEANUP
###################

"${SSH_CMD[@]}" "${REMOTE}" "
  set -e
  cd '${REMOTE_SNAP_DIR}'
  KEEP='${SNAPSHOT_KEEP}'

  snaps=\$(ls -1d [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9] 2>/dev/null | sort || true)
  count=\$(printf '%s\n' \"\$snaps\" | sed '/^$/d' | wc -l | tr -d ' ')

  if [ \"\$count\" -gt \"\$KEEP\" ]; then
    del=\$(printf '%s\n' \"\$snaps\" | head -n \$((count-KEEP)))
    for d in \$del; do
      rm -rf -- \"\$d\"
    done
  fi
" || {
  err "Retention cleanup failed on remote (snapshot ${SNAP} is still valid)."
  [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]] && telegram_send "Backup WARNING on ${REMOTE_HOST}
Snapshot: ${SNAP}
Retention cleanup failed."
  exit 1
}

########################
# OPTIONAL SUCCESS NOTIFY
########################

if [[ "${TELEGRAM_NOTIFY_ON_SUCCESS}" == "1" ]]; then
  telegram_send "Backup OK on ${REMOTE_HOST}
Snapshot: ${SNAP}
Source: ${LOCAL_BASE_DIR}
Dest: ${REMOTE_SNAP_DIR}/${SNAP}
Kept: last ${SNAPSHOT_KEEP}"
fi

echo "Backup OK: ${SNAP} -> ${REMOTE}:${FINAL_REMOTE}"
exit 0
