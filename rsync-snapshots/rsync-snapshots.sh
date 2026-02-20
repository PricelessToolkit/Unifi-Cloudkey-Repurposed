#!/usr/bin/env bash
# rsync-snapshots.sh (safer + more portable)
#
# Snapshot backups over SSH using rsync + hard-linking (--link-dest), with:
# - remote snapshots named YYYY-MM-DD_HHMMSS
# - tmp/incomplete snapshots created on the SAME remote volume
# - keep last N snapshots
# - Telegram notify on failure (optionally on success)
# - Safety guard: require specific paths exist under LOCAL_BASE_DIR before running
# - Configurable excludes: extensions and directory names
# - Pre-flight remote disk space check (bytes threshold) + Telegram notify if low
# - Intentional incomplete handling: DO NOT delete any existing .incomplete-* unless allowed
# - Remote lockdir to prevent concurrent runs (covers rsync + finalize)
#
# Safer changes vs your version:
# - ALWAYS releases remote lock on exit (success OR failure)
# - Remote finalize runs with bash (not /bin/sh), avoiding dash/pipefail/[[ issues
# - Portable listing for snapshots/incomplete dirs without relying on `find -printf` (BusyBox-safe)
# - Optional rsync resume support (--partial-dir inside tmp snapshot)
# - Optional --delete-excluded toggle
#
# Requirements (local): rsync, ssh, curl (only if you want Telegram)
# Requirements (remote): rsync, bash, coreutils (mkdir, mv, ln, rm), df, awk, ls, sed, head, wc, readlink

set -euo pipefail
IFS=$'\n\t'

###############
# CONFIG START
###############

# Local source base directory (the whole tree under this will be backed up)
LOCAL_BASE_DIR="/data"   # <-- CHANGE THIS

# Safety guard: require these paths to exist under LOCAL_BASE_DIR before running.
# Space-separated, relative to LOCAL_BASE_DIR.
# Set empty to disable.
REQUIRED_PATHS="photos documents"  # <-- CHANGE OR SET TO ""

# Remote SSH target
REMOTE_USER="root"                 # <-- consider a non-root user
REMOTE_HOST="uckg2plus.lab.lan"
REMOTE_PORT="22"

# Remote base directory where snapshots/ will live (on your HDD volume)
REMOTE_BASE_DIR="/volume1/backup/rsync"
REMOTE_SNAP_DIR="${REMOTE_BASE_DIR}/snapshots"

# Retention: keep last N finished snapshots
SNAPSHOT_KEEP="10"

# Extra safety: cap how many deletions rsync is allowed to do in one run.
# This is a strong guard against backing up an empty/mis-mounted source with --delete enabled.
# Set to 0 to disable.
MAX_DELETE="50000"

# Telegram notifications (optional)
TELEGRAM_NOTIFY_ON_FAILURE="1"   # 1 = yes, 0 = no
TELEGRAM_NOTIFY_ON_SUCCESS="0"   # 1 = yes, 0 = no (default off)
TELEGRAM_BOT_TOKEN=""            # e.g. "123456:ABC-DEF..."  (leave empty to disable)
TELEGRAM_CHAT_ID=""              # e.g. "-1001234567890" or "123456789" (leave empty to disable)

# --------------------------
# EXCLUDES (optional)
# --------------------------

# Extensions to exclude anywhere (space-separated, with or without leading dot)
# Example: "mp4 mp3 iso"
EXCLUDE_EXTENSIONS="mp4 mp3"

# Directory names to exclude anywhere in the tree (names only, space-separated)
# Example: "pictures trash .Trash-1000 .Trashes @eaDir"
EXCLUDE_DIRNAMES="pictures trash"

# If 1, also delete excluded files/dirs from destination snapshot (more “truthful” mirrors)
# If 0, excluded things may persist in dest if they existed previously.
DELETE_EXCLUDED="0"

# SSH keepalive (helps stability; not a retry loop)
SSH_SERVER_ALIVE_INTERVAL="30"
SSH_SERVER_ALIVE_COUNT_MAX="6"

# Optional: stay on one filesystem (prevents crossing mounts under LOCAL_BASE_DIR)
ONE_FILE_SYSTEM="0"  # 1 = enable, 0 = disable

# Optional: preserve ACLs and xattrs (only if you need them and remote supports it)
PRESERVE_ACL_XATTR="0"  # 1 = add -A -X, 0 = no

# Optional: preserve hardlinks *within the source* (can be expensive on very large trees).
# This is NOT required for snapshot hardlinking (--link-dest handles that).
PRESERVE_SOURCE_HARDLINKS="0"  # 1 = include -H, 0 = no

# Optional: allow rsync resume within tmp snapshot (recommended for unstable links)
RSYNC_RESUME_PARTIAL="1"  # 1 = use --partial-dir in tmp, 0 = disable

# SSH host key checking (recommended for unattended jobs).
# "yes" is safest but requires known_hosts to be set up.
# You can use "accept-new" on newer OpenSSH if you prefer.
SSH_STRICT_HOST_KEY_CHECKING="yes"  # yes|no|accept-new

# --------------------------
# Remote disk-space preflight
# --------------------------
# Minimum free space required on remote filesystem containing REMOTE_SNAP_DIR.
# If free space is below this threshold, the script aborts BEFORE creating tmp dirs / running rsync.
# Set to 0 to disable.
REMOTE_MIN_FREE_BYTES=0 # $((50 * 1024 * 1024 * 1024))  # 50 GiB

# Also optionally enforce a minimum percent free (integer 0-100). Set empty to disable.
REMOTE_MIN_FREE_PERCENT=""  # e.g. "5" for 5%

# --------------------------
# Incomplete snapshot handling
# --------------------------
# By default, we REFUSE to delete ANY existing .incomplete-* directory.
# This prevents losing evidence from a prior failed run.
# If you want auto-cleanup, set to "1" (it will only delete TMP_REMOTE for THIS run if it exists).
ALLOW_DELETE_EXISTING_TMP_FOR_THIS_RUN="1"  # 1 = ok to delete THIS run's tmp dir, 0 = refuse if it exists

#############
# CONFIG END
#############

err() { echo "ERROR: $*" >&2; }

telegram_send() {
  local msg="$1"
  [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" ]] && return 0
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
[[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" || "${TELEGRAM_NOTIFY_ON_SUCCESS}" == "1" ]] && need_cmd curl || true

REMOTE="${REMOTE_USER}@${REMOTE_HOST}"

# Snapshot name (local machine time) — include seconds to avoid collisions
SNAP="$(date +%F_%H%M%S)"
TMP_NAME=".incomplete-${SNAP}"
TMP_REMOTE="${REMOTE_SNAP_DIR}/${TMP_NAME}"
FINAL_REMOTE="${REMOTE_SNAP_DIR}/${SNAP}"
LATEST_REMOTE="${REMOTE_SNAP_DIR}/latest"
LOCKDIR_REMOTE="${REMOTE_SNAP_DIR}/.rsync-snapshots.lockdir"

# Track stage for better failure messages
STAGE="init"
LOCK_ACQUIRED="0"

RSYNC_RSH=""
SSH_CMD=()

cleanup_lock_best_effort() {
  [[ "${LOCK_ACQUIRED}" != "1" ]] && return 0
  [[ -z "${REMOTE}" || -z "${LOCKDIR_REMOTE}" ]] && return 0
  if [[ ${#SSH_CMD[@]} -gt 0 ]]; then
    "${SSH_CMD[@]}" "${REMOTE}" "rmdir '${LOCKDIR_REMOTE}' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  fi
}

on_exit() {
  local exit_code=$?

  # Always try to release the lock on any exit (success OR failure)
  cleanup_lock_best_effort
  LOCK_ACQUIRED="0"

  if [[ $exit_code -ne 0 ]]; then
    err "Failed at stage: ${STAGE} (exit: ${exit_code})"
    if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
      telegram_send "Backup FAILED on ${REMOTE_HOST}
Stage: ${STAGE}
Snapshot: ${SNAP}
Exit: ${exit_code}
Tmp: ${TMP_NAME} (may exist)"
    fi
  fi

  exit $exit_code
}
trap on_exit EXIT

############################################
# SAFETY CHECKS (before touching the remote)
############################################
STAGE="safety-checks"

# 1) Ensure source exists
if [[ ! -d "${LOCAL_BASE_DIR}" ]]; then
  err "LOCAL_BASE_DIR does not exist: ${LOCAL_BASE_DIR}"
  exit 1
fi

# Refuse obviously dangerous values
if [[ "${LOCAL_BASE_DIR}" == "/" || -z "${LOCAL_BASE_DIR}" ]]; then
  err "Refusing to run with LOCAL_BASE_DIR='${LOCAL_BASE_DIR}'"
  exit 1
fi

# 2) Validate retention value
if ! [[ "${SNAPSHOT_KEEP}" =~ ^[0-9]+$ ]] || [[ "${SNAPSHOT_KEEP}" -lt 1 ]]; then
  err "SNAPSHOT_KEEP must be a positive integer, got: ${SNAPSHOT_KEEP}"
  exit 1
fi

# 3) Validate MAX_DELETE
if ! [[ "${MAX_DELETE}" =~ ^[0-9]+$ ]]; then
  err "MAX_DELETE must be an integer (0 disables), got: ${MAX_DELETE}"
  exit 1
fi

# 4) Validate remote disk thresholds
if ! [[ "${REMOTE_MIN_FREE_BYTES}" =~ ^[0-9]+$ ]]; then
  err "REMOTE_MIN_FREE_BYTES must be an integer (0 disables), got: ${REMOTE_MIN_FREE_BYTES}"
  exit 1
fi
if [[ -n "${REMOTE_MIN_FREE_PERCENT}" ]]; then
  if ! [[ "${REMOTE_MIN_FREE_PERCENT}" =~ ^[0-9]+$ ]] || [[ "${REMOTE_MIN_FREE_PERCENT}" -gt 100 ]]; then
    err "REMOTE_MIN_FREE_PERCENT must be integer 0..100 or empty, got: ${REMOTE_MIN_FREE_PERCENT}"
    exit 1
  fi
fi

# 5) Safety guard: require specific folders/files exist
if [[ -n "${REQUIRED_PATHS}" ]]; then
  for p in ${REQUIRED_PATHS}; do
    if [[ ! -e "${LOCAL_BASE_DIR%/}/$p" ]]; then
      err "Required path missing: ${LOCAL_BASE_DIR%/}/$p. Refusing to run."
      exit 1
    fi
  done
fi

########################
# SSH / REMOTE PREP
########################
STAGE="remote-prep"

# Build SSH command string for rsync's -e
RSYNC_RSH="ssh -p ${REMOTE_PORT} -o BatchMode=yes -o StrictHostKeyChecking=${SSH_STRICT_HOST_KEY_CHECKING} -o ServerAliveInterval=${SSH_SERVER_ALIVE_INTERVAL} -o ServerAliveCountMax=${SSH_SERVER_ALIVE_COUNT_MAX}"

# Also keep an SSH array for direct ssh calls (safe quoting)
SSH_CMD=(
  ssh -p "${REMOTE_PORT}"
  -o BatchMode=yes
  -o StrictHostKeyChecking="${SSH_STRICT_HOST_KEY_CHECKING}"
  -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL}"
  -o ServerAliveCountMax="${SSH_SERVER_ALIVE_COUNT_MAX}"
)

# Ensure remote directories exist
"${SSH_CMD[@]}" "${REMOTE}" "mkdir -p '${REMOTE_SNAP_DIR}'" >/dev/null

# Remote must have bash for finalize script (safer + consistent)
"${SSH_CMD[@]}" "${REMOTE}" "command -v bash >/dev/null 2>&1" || {
  err "Remote missing 'bash'. Install bash or rewrite remote finalize script to POSIX sh."
  exit 1
}

############################################
# PRE-FLIGHT: REMOTE DISK SPACE CHECK
############################################
STAGE="remote-disk-check"

# Use df -P -k (portable). Convert KB -> bytes.
REMOTE_DF_OUT="$("${SSH_CMD[@]}" "${REMOTE}" "df -P -k '${REMOTE_SNAP_DIR}' | awk 'NR==2{print \$4\" \"\$5\" \"\$6}'" 2>/dev/null || true)"
if [[ -z "${REMOTE_DF_OUT}" ]]; then
  err "Could not read remote disk usage for: ${REMOTE_SNAP_DIR}"
  exit 1
fi

REMOTE_AVAIL_KB="$(printf '%s\n' "${REMOTE_DF_OUT}" | awk '{print $1}')"
REMOTE_USE_PCT="$(printf '%s\n' "${REMOTE_DF_OUT}" | awk '{gsub(/%/,"",$2); print $2}')"
REMOTE_MOUNT="$(printf '%s\n' "${REMOTE_DF_OUT}" | awk '{print $3}')"

REMOTE_AVAIL_BYTES=$((REMOTE_AVAIL_KB * 1024))

# bytes threshold
if [[ "${REMOTE_MIN_FREE_BYTES}" -gt 0 ]] && [[ "${REMOTE_AVAIL_BYTES}" -lt "${REMOTE_MIN_FREE_BYTES}" ]]; then
  err "Remote free space too low on ${REMOTE_HOST} (${REMOTE_MOUNT}): avail=${REMOTE_AVAIL_BYTES} bytes, required>=${REMOTE_MIN_FREE_BYTES} bytes"
  if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
    telegram_send "Backup ABORTED on ${REMOTE_HOST} (low disk space)
Mount: ${REMOTE_MOUNT}
Avail: ${REMOTE_AVAIL_BYTES} bytes
Required: ${REMOTE_MIN_FREE_BYTES} bytes
Path: ${REMOTE_SNAP_DIR}"
  fi
  exit 20
fi

# percent free threshold (if set): percent free = 100 - use%
if [[ -n "${REMOTE_MIN_FREE_PERCENT}" ]]; then
  REMOTE_FREE_PCT=$((100 - REMOTE_USE_PCT))
  if [[ "${REMOTE_FREE_PCT}" -lt "${REMOTE_MIN_FREE_PERCENT}" ]]; then
    err "Remote percent free too low on ${REMOTE_HOST} (${REMOTE_MOUNT}): free=${REMOTE_FREE_PCT}%, required>=${REMOTE_MIN_FREE_PERCENT}%"
    if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
      telegram_send "Backup ABORTED on ${REMOTE_HOST} (low disk space %)
Mount: ${REMOTE_MOUNT}
Free: ${REMOTE_FREE_PCT}%
Required: ${REMOTE_MIN_FREE_PERCENT}%
Path: ${REMOTE_SNAP_DIR}"
    fi
    exit 21
  fi
fi

############################################
# ACQUIRE REMOTE LOCK (prevents concurrent runs)
############################################
STAGE="lock"

# Atomic lock: mkdir succeeds only if not existing
if ! "${SSH_CMD[@]}" "${REMOTE}" "mkdir '${LOCKDIR_REMOTE}' 2>/dev/null"; then
  err "Another backup run appears to be in progress (lock exists): ${LOCKDIR_REMOTE}"
  if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
    telegram_send "Backup ABORTED on ${REMOTE_HOST} (lock busy)
Lock: ${LOCKDIR_REMOTE}
Path: ${REMOTE_SNAP_DIR}"
  fi
  exit 25
fi
LOCK_ACQUIRED="1"

############################################
# INTENTIONAL INCOMPLETE HANDLING
############################################
STAGE="tmp-dir"

# BusyBox-safe listing of existing .incomplete-* dirs (names only), best-effort.
REMOTE_INCOMPLETE_LIST="$(
  "${SSH_CMD[@]}" "${REMOTE}" "
    set -e
    cd '${REMOTE_SNAP_DIR}'
    (ls -1d .incomplete-* 2>/dev/null || true) | sed 's|.*/||' | sort
  " 2>/dev/null || true
)"

# If there are incomplete dirs and they are not exactly TMP_NAME, refuse (to preserve evidence)
if [[ -n "${REMOTE_INCOMPLETE_LIST}" ]]; then
  OTHER_INCOMPLETE="$(printf '%s\n' "${REMOTE_INCOMPLETE_LIST}" | awk -v tmp="${TMP_NAME}" 'NF && $0 != tmp {print $0}')"
  if [[ -n "${OTHER_INCOMPLETE}" ]]; then
    err "Found existing remote incomplete snapshot(s). Refusing to proceed to avoid overwriting evidence:"
    printf '%s\n' "${OTHER_INCOMPLETE}" >&2
    if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
      telegram_send "Backup ABORTED on ${REMOTE_HOST} (existing incomplete snapshot(s))
Path: ${REMOTE_SNAP_DIR}
Existing:
${OTHER_INCOMPLETE}"
    fi
    exit 22
  fi
fi

# If TMP_NAME already exists, only delete it if ALLOW_DELETE_EXISTING_TMP_FOR_THIS_RUN=1
TMP_EXISTS="$("${SSH_CMD[@]}" "${REMOTE}" "test -d '${TMP_REMOTE}' && echo yes || echo no" 2>/dev/null || echo no)"
if [[ "${TMP_EXISTS}" == "yes" ]]; then
  if [[ "${ALLOW_DELETE_EXISTING_TMP_FOR_THIS_RUN}" != "1" ]]; then
    err "Tmp snapshot dir already exists for this run (${TMP_REMOTE}) and deletion is disabled. Refusing."
    if [[ "${TELEGRAM_NOTIFY_ON_FAILURE}" == "1" ]]; then
      telegram_send "Backup ABORTED on ${REMOTE_HOST} (tmp already exists)
Tmp: ${TMP_NAME}
Path: ${REMOTE_SNAP_DIR}
Set ALLOW_DELETE_EXISTING_TMP_FOR_THIS_RUN=1 to allow cleanup."
    fi
    exit 23
  fi
  "${SSH_CMD[@]}" "${REMOTE}" "rm -rf '${TMP_REMOTE}'" >/dev/null
fi

# Create remote tmp/incomplete directory (on same filesystem as final)
"${SSH_CMD[@]}" "${REMOTE}" "mkdir -p '${TMP_REMOTE}'" >/dev/null

# Determine if latest is valid (exists and points to an existing directory)
USE_LINK_DEST="0"
if "${SSH_CMD[@]}" "${REMOTE}" "set -e; cd '${REMOTE_SNAP_DIR}'; test -L 'latest' && t=\$(readlink 'latest') && test -d \"\$t\""; then
  USE_LINK_DEST="1"
fi

################
# RSYNC OPTIONS
################
STAGE="rsync"

RSYNC_OPTS=(-a --numeric-ids --delete --delete-delay)

# Optional: remove excluded files from destination snapshot too
if [[ "${DELETE_EXCLUDED}" == "1" ]]; then
  RSYNC_OPTS+=(--delete-excluded)
fi

# Optional: resume partial transfers safely inside tmp snapshot
if [[ "${RSYNC_RESUME_PARTIAL}" == "1" ]]; then
  RSYNC_OPTS+=(--partial --partial-dir=".rsync-partial")
fi

if [[ "${PRESERVE_SOURCE_HARDLINKS}" == "1" ]]; then
  RSYNC_OPTS+=(-H)
fi

if [[ "${PRESERVE_ACL_XATTR}" == "1" ]]; then
  RSYNC_OPTS+=(-A -X)
fi

if [[ "${ONE_FILE_SYSTEM}" == "1" ]]; then
  RSYNC_OPTS+=(--one-file-system)
fi

if [[ "${MAX_DELETE}" -gt 0 ]]; then
  RSYNC_OPTS+=(--max-delete="${MAX_DELETE}")
fi

if [[ -n "${EXCLUDE_EXTENSIONS}" ]]; then
  for ext in ${EXCLUDE_EXTENSIONS}; do
    ext="${ext#.}"
    [[ -n "${ext}" ]] && RSYNC_OPTS+=(--exclude="*.${ext}")
  done
fi

if [[ -n "${EXCLUDE_DIRNAMES}" ]]; then
  for d in ${EXCLUDE_DIRNAMES}; do
    [[ -z "${d}" ]] && continue
    RSYNC_OPTS+=(--exclude="*/${d}/")
  done
fi

if [[ "${USE_LINK_DEST}" == "1" ]]; then
  RSYNC_OPTS+=(--link-dest="../latest")
fi

SRC="${LOCAL_BASE_DIR%/}/"
DEST="${REMOTE}:${TMP_REMOTE}/"

set +e
rsync "${RSYNC_OPTS[@]}" -e "${RSYNC_RSH}" "${SRC}" "${DEST}"
RSYNC_EXIT=$?
set -e

if [[ "${RSYNC_EXIT}" -ne 0 ]]; then
  err "rsync failed with exit code ${RSYNC_EXIT}"
  # Leave .incomplete snapshot in place for inspection.
  exit "${RSYNC_EXIT}"
fi

############################################
# FINALIZE + UPDATE LATEST + RETENTION
############################################
STAGE="finalize"

# Finalize remotely using bash, and avoid find -printf (BusyBox-safe).
REMOTE_FINALIZE_SCRIPT=$(cat <<'EOS'
set -euo pipefail
IFS=$'\n\t'

snapdir="$1"
snap="$2"
tmp="$3"
keep="$4"

cd "$snapdir"

tmp_path="$snapdir/$tmp"
final_path="$snapdir/$snap"

# Finalize (atomic if same filesystem)
mv -- "$tmp_path" "$final_path"

# Update latest symlink
ln -sfn "$snap" latest

# Retention: keep last N finished snapshots
# BusyBox-safe listing: glob pattern + sort
snaps="$( (ls -1d ????-??-??_?????? 2>/dev/null || true) | sed 's|.*/||' | LC_ALL=C sort )"
count="$(printf '%s\n' "$snaps" | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "$count" -gt "$keep" ]]; then
  del="$(printf '%s\n' "$snaps" | head -n $((count-keep)) )"
  # shellcheck disable=SC2086
  for d in $del; do
    rm -rf -- "$d"
  done
fi
EOS
)

# Run finalize script via bash on the remote
"${SSH_CMD[@]}" "${REMOTE}" "
  set -e
  snapdir='${REMOTE_SNAP_DIR}'
  snap='${SNAP}'
  tmp='${TMP_NAME}'
  keep='${SNAPSHOT_KEEP}'
  bash -s -- \"\$snapdir\" \"\$snap\" \"\$tmp\" \"\$keep\" <<'EOF'
${REMOTE_FINALIZE_SCRIPT}
EOF
" >/dev/null

########################
# OPTIONAL SUCCESS NOTIFY
########################
STAGE="success"

if [[ "${TELEGRAM_NOTIFY_ON_SUCCESS}" == "1" ]]; then
  telegram_send "Backup OK on ${REMOTE_HOST}
Snapshot: ${SNAP}
Source: ${LOCAL_BASE_DIR}
Dest: ${REMOTE_SNAP_DIR}/${SNAP}
Kept: last ${SNAPSHOT_KEEP}
Link-dest: ${USE_LINK_DEST}
Max-delete: ${MAX_DELETE}"
fi

echo "Backup OK: ${SNAP} -> ${REMOTE}:${REMOTE_SNAP_DIR}/${SNAP}"
exit 0
