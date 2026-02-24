# rsync-snapshots.sh — Snapshot Backups over SSH

A safer snapshot-based backup script using `rsync` and hard links (`--link-dest`).

Each run:

- Creates snapshot: `YYYY-MM-DD_HHMMSS`
- Uses `.incomplete-*` temp directory
- Atomically renames on success
- Updates `latest` symlink
- Enforces retention (keep last N)
- Prevents concurrent runs (remote lockdir)
- Performs remote disk space pre-check
- Protects against accidental mass deletion
- Optionally sends Telegram notifications

---

# 1. Requirements

## Local
- bash
- rsync
- ssh
- curl (optional, for Telegram)

## Remote
- rsync
- bash
- coreutils (mkdir, mv, ln, rm, ls, awk, sed, head, wc, readlink)
- df

---

# 2. Configuration

Edit the CONFIG section in the script.

## Required

```bash
LOCAL_BASE_DIR="/data"

REMOTE_USER="root"
REMOTE_HOST="server.lan"
REMOTE_PORT="22"

REMOTE_BASE_DIR="/volume1/backup/rsync"

SNAPSHOT_KEEP="10"
```

---

# 3. Safety Features

## Required Paths Guard

Prevents running if critical paths are missing:

```bash
REQUIRED_PATHS="photos documents"
```

Set empty to disable.

---

## Max Delete Protection

Limits how many deletions rsync can perform:

```bash
MAX_DELETE="50000"
```

Prevents wiping destination if source is empty/mis-mounted.

Set `0` to disable.

---

## Remote Lock

Creates:

```
.rsync-snapshots.lockdir
```

Prevents concurrent runs.

---

## Incomplete Snapshot Protection

- Script refuses to overwrite existing `.incomplete-*`
- Leaves failed snapshots for inspection
- Atomic rename only on success

---

## Remote Disk Space Check

Optional thresholds:

```bash
REMOTE_MIN_FREE_BYTES=0
REMOTE_MIN_FREE_PERCENT=""
```

If free space is below threshold, backup aborts before rsync.

---

# 4. Exclusions

## By extension

```bash
EXCLUDE_EXTENSIONS="mp4 mp3"
```

## By directory name

```bash
EXCLUDE_DIRNAMES="pictures trash"
```

## Delete excluded from destination

```bash
DELETE_EXCLUDED="1"
```

---

# 5. Optional Features

## Resume support

```bash
RSYNC_RESUME_PARTIAL="1"
```

Enables `--partial-dir` inside temp snapshot.

## Stay on one filesystem

```bash
ONE_FILE_SYSTEM="1"
```

## Preserve ACLs / xattrs

```bash
PRESERVE_ACL_XATTR="1"
```

## Preserve source hardlinks

```bash
PRESERVE_SOURCE_HARDLINKS="1"
```

---

# 6. SSH Setup

Test:

```bash
ssh -p 22 root@server.lan
```

Use SSH keys for automation.

Host key checking mode:

```bash
SSH_STRICT_HOST_KEY_CHECKING="yes"
```

---

# 7. Snapshot Structure (Remote)

```
/volume1/backup/rsync/snapshots/
    2026-02-20_013045/
    2026-02-21_021512/
    latest -> 2026-02-21_021512
    .rsync-snapshots.lockdir
```

Temporary during run:

```
.incomplete-2026-02-22_021533/
```

---

# 8. Running

```bash
./rsync-snapshots.sh
```

On success:

```
Backup OK: 2026-02-24_021533 -> user@host:/volume1/backup/rsync/snapshots/...
```

---

# 9. Cron Example

```cron
15 2 * * * /full/path/rsync-snapshots.sh >> /var/log/rsync-snapshots.log 2>&1
```

Use absolute paths.

---

# 10. Telegram Notifications (Optional)

```bash
TELEGRAM_NOTIFY_ON_FAILURE="1"
TELEGRAM_NOTIFY_ON_SUCCESS="0"
TELEGRAM_BOT_TOKEN="..."
TELEGRAM_CHAT_ID="..."
```

Failure notifications recommended.
Success notifications optional.

---

# 11. Notes

- Source contents are copied, not the directory itself.
- Hard links ensure unchanged files consume no additional space.
- Snapshots are independent.
- Safe to interrupt — incomplete snapshots are not finalized.
- Retention only deletes fully completed snapshots.
