# rsync-snapshots.sh — Snapshot Backups over SSH

This script creates rsync-based snapshot backups over SSH using hard links (`--link-dest`) for space efficiency.

Each run:
- Creates a new snapshot: `YYYY-MM-DD_HHMM`
- Uses a temporary `.incomplete-*` directory
- Updates `latest` symlink
- Deletes old snapshots beyond retention limit
- Optionally sends Telegram notifications
- Supports configurable exclusions

---

# 1. Requirements

## Local machine
- bash
- rsync
- ssh
- curl (only if using Telegram notifications)

## Remote machine
- rsync
- coreutils (mkdir, mv, ln, rm, ls, sort, readlink)

---

# 2. Installation

Clone your repository or create a folder:

```bash
mkdir -p scripts
nano scripts/rsync-snapshots.sh
```

Paste the script into the file.

Make it executable:

```bash
chmod +x scripts/rsync-snapshots.sh
```

(Optional) Add to Git:

```bash
git add scripts/rsync-snapshots.sh
git commit -m "Add rsync snapshot backup script"
```

---

# 3. Configuration

Open the script and edit the CONFIG section.

## Required settings

Set your local source:

```bash
LOCAL_BASE_DIR="/data"
```

Set remote SSH target:

```bash
REMOTE_USER="root"
REMOTE_HOST="your.server.lan"
REMOTE_PORT="22"
```

Set remote backup directory:

```bash
REMOTE_BASE_DIR="/volume1/backup/rsync"
```

## Retention policy

Keep last N snapshots:

```bash
SNAPSHOT_KEEP="10"
```

---

# 4. Safety Guard (Recommended)

To prevent accidental empty backups:

```bash
REQUIRED_PATHS="photos documents"
```

The script will refuse to run if those paths do not exist under LOCAL_BASE_DIR.

Set empty to disable:

```bash
REQUIRED_PATHS=""
```

---

# 5. SSH Setup (Recommended)

Test SSH:

```bash
ssh -p 22 root@your.server.lan "echo ok"
```

If it asks for password every time, set up SSH keys:

Generate key:

```bash
ssh-keygen -t ed25519 -C "backup-key"
```

Copy key to remote:

```bash
ssh-copy-id -p 22 root@your.server.lan
```

Test again:

```bash
ssh root@your.server.lan
```

---

# 6. Exclusions Configuration

The script supports multiple exclusion methods.

## A. Exclude by file extension

Exclude file types anywhere in the tree:

```bash
EXCLUDE_EXTENSIONS="mp4 mp3 iso"
```

You can include dots or not:

```bash
EXCLUDE_EXTENSIONS=".mp4 .mp3"
```

---

## B. Exclude directory names (anywhere)

Exclude directories by name anywhere in the tree:

```bash
EXCLUDE_DIRNAMES="pictures trash"
```

Common NAS/system junk example:

```bash
EXCLUDE_DIRNAMES="pictures trash .Trash-1000 .Trashes @eaDir #recycle"
```

---

## C. Custom rsync patterns

Advanced patterns (newline separated):

```bash
EXCLUDE_PATTERNS=$'*.tmp\ncache/\nDownloads/\n**/.DS_Store'
```

---

## D. Excludes file (optional)

Create a file:

```bash
nano excludes.txt
```

Example content:

```
*.tmp
cache/
Downloads/
**/.DS_Store
```

Set in script:

```bash
EXCLUDE_FILE="/path/to/excludes.txt"
```

---

# 7. Running the Backup

Run manually:

```bash
./scripts/rsync-snapshots.sh
```

On success:

```
Backup OK: YYYY-MM-DD_HHMM -> user@host:/volume1/backup/rsync/snapshots/YYYY-MM-DD_HHMM
```

---

# 8. Remote Snapshot Structure

Remote directory layout:

```
/volume1/backup/rsync/snapshots/
    2026-02-20_0130/
    2026-02-21_0130/
    latest -> 2026-02-21_0130
```

Temporary directory during backup:

```
.incomplete-YYYY-MM-DD_HHMM/
```

If backup fails, the incomplete directory remains for inspection.

---

# 9. Automatic Scheduling (cron)

Edit crontab:

```bash
crontab -e
```

Example: run every day at 02:15

```cron
15 2 * * * /full/path/to/scripts/rsync-snapshots.sh >> /var/log/rsync-snapshots.log 2>&1
```

Important:
- Use full absolute paths
- Ensure cron user has SSH key access

---

# 10. Telegram Notifications (Optional)

Set:

```bash
TELEGRAM_NOTIFY_ON_FAILURE="1"
TELEGRAM_NOTIFY_ON_SUCCESS="0"
TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
TELEGRAM_CHAT_ID="-1001234567890"
```

Failure notifications are recommended.
Success notifications are optional (can be noisy).

---

# 11. Troubleshooting

## SSH fails
Test manually:

```bash
ssh root@your.server.lan
```

## Permission denied on remote
Ensure remote directory exists and is writable by SSH user.

## Excludes not working
- Directory excludes match directory names anywhere.
- For specific paths, use EXCLUDE_PATTERNS or EXCLUDE_FILE.

---

# 12. Notes

- The source directory contents are copied, not the directory itself.
- Hard links make unchanged files consume no additional space.
- Snapshots are independent and safe to browse or restore from.
- Safe to interrupt — incomplete snapshots are never marked as valid.

---

You can now commit this README to GitHub.
