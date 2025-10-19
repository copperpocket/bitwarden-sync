#!/usr/bin/env bash

# ------------------------
# Bitwarden Backup & Sync
# ------------------------
# Automates backup/export from source vault and restore/import to destination vault.
# Logs all output to ./bitwarden_sync.log (overwrites each run)
# Designed to be run via cron. DRY_RUN is disabled by default.
# ------------------------

# Change to working directory
cd "$(dirname "$0")"

# Load environment variables from .env if present
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Log everything to console and file (overwrite log each run)
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bitwarden_sync_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee "$LOG_FILE") 2>&1

# Delete log files older than 30 days
find "$LOG_DIR" -type f -name "bitwarden_sync_*.log" -mtime +30 -print -exec rm -f {} \;

# DRY_RUN: 1 = simulate changes (no deletes/imports), 0 = perform actual sync
DRY_RUN=0

set -euo pipefail
IFS=$'\n\t'

# === Configurable ===
RATE_LIMIT_DELAY=0.1   # seconds to sleep between destructive API calls
BACKUP_DIR="./backups"
LOG_PREFIX="[bitwarden-sync]"

# ------------------------
# Helper: cleanup temporary files
# ------------------------
cleanup() {
  echo "$LOG_PREFIX Cleaning up temporary session files..."
  rm -f /tmp/bw_session_source.$$ /tmp/bw_session_dest.$$ 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "$LOG_PREFIX Starting Bitwarden sync at $(date)"

# Ensure consistent locale for CLI tools
export LC_CTYPE=C
export LC_ALL=C

# Decrypt archive password for backups
export BW_TAR_PASS=$(openssl enc -d -aes-256-cbc -in bitwarden_tar_password.enc -pass file:bitwarden_tar_keyfile)

# ------------------------
# Source Vault Configuration
# ------------------------
export BW_ACCOUNT_SOURCE="${BW_ACCOUNT_SOURCE:-}"
BW_PASS_SOURCE=$(openssl enc -d -aes-256-cbc -in bitwarden_backup_password.enc -pass file:bitwarden_backup_keyfile)
export BW_CLIENTID_SOURCE="${BW_CLIENTID_SOURCE:-}"
BW_CLIENTSECRET_SOURCE=$(openssl enc -d -aes-256-cbc -in bitwarden_source_password.enc -pass file:bitwarden_source_keyfile)
export BW_SERVER_SOURCE="${BW_SERVER_SOURCE:-}"

# ------------------------
# Destination Vault Configuration
# ------------------------
export BW_ACCOUNT_DEST="${BW_ACCOUNT_DEST:-}"
BW_PASS_DEST=$(openssl enc -d -aes-256-cbc -in bitwarden_restore_password.enc -pass file:bitwarden_restore_keyfile)
export BW_CLIENTID_DEST="${BW_CLIENTID_DEST:-}"
BW_CLIENTSECRET_DEST=$(openssl enc -d -aes-256-cbc -in bitwarden_dest_password.enc -pass file:bitwarden_dest_keyfile)
export BW_SERVER_DEST="${BW_SERVER_DEST:-}"

mkdir -p "$BACKUP_DIR"

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo "$LOG_PREFIX Start Time: $START_TIME"

# Use source API keys for backup
export BW_CLIENTID=${BW_CLIENTID_SOURCE}
export BW_CLIENTSECRET=${BW_CLIENTSECRET_SOURCE}

# ========================
# Backup / Export
# ========================
echo "$LOG_PREFIX ### Backup - Start ###"

SOURCE_EXPORT_OUTPUT_BASE="bw_export_"
TIMESTAMP=$(date "+%Y%m%d%H%M%S")
SOURCE_OUTPUT_FILE_JSON="$BACKUP_DIR/${SOURCE_EXPORT_OUTPUT_BASE}${TIMESTAMP}.json"

# Remove old encrypted backups (>30 days)
echo "$LOG_PREFIX Removing encrypted backups older than 30 days..."
find "$BACKUP_DIR" -type f -name "bw_export_*.tar.gz.enc" -mtime +30 -print -exec rm -f {} \; || true

# Remove stale JSON exports (>7 days)
echo "$LOG_PREFIX Removing old JSON exports..."
find "$BACKUP_DIR" -maxdepth 1 -type f -name "bw_export_*.json" -mtime +7 -print -exec rm -f {} \; || true

echo "$LOG_PREFIX Logging out any previous sessions (ignore errors)..."
bw logout 2>/dev/null || true

# Login and unlock source vault
echo "$LOG_PREFIX Logging into Source Bitwarden Server..."
bw config server "$BW_SERVER_SOURCE"
bw login "$BW_ACCOUNT_SOURCE" --apikey --raw

echo "$LOG_PREFIX Unlocking source vault..."
BW_SESSION_SOURCE=$(bw unlock "$BW_PASS_SOURCE" --raw)
echo "$BW_SESSION_SOURCE" >/tmp/bw_session_source.$$
chmod 600 /tmp/bw_session_source.$$

echo "$LOG_PREFIX Exporting all items from source vault to JSON..."
bw --session "$BW_SESSION_SOURCE" export --format json --output "$SOURCE_OUTPUT_FILE_JSON"
echo "$LOG_PREFIX Source export complete: $SOURCE_OUTPUT_FILE_JSON"

# Dry-run info
if [ "$DRY_RUN" -eq 1 ]; then
  items_to_import=$(jq '.items | length' "$SOURCE_OUTPUT_FILE_JSON" 2>/dev/null || echo 0)
  folders_to_import=$(jq '.folders | length' "$SOURCE_OUTPUT_FILE_JSON" 2>/dev/null || echo 0)
  attachments_to_import=$(jq '.attachments | length' "$SOURCE_OUTPUT_FILE_JSON" 2>/dev/null || echo 0)
  echo "$LOG_PREFIX [DRY-RUN] Source items: $items_to_import, folders: $folders_to_import, attachments: $attachments_to_import"
fi

# Compress and encrypt export
ARCHIVE_FILE="$BACKUP_DIR/${SOURCE_EXPORT_OUTPUT_BASE}${TIMESTAMP}.tar.gz.enc"
echo "$LOG_PREFIX Archiving and encrypting export to $ARCHIVE_FILE..."
tar -C "$BACKUP_DIR" -czf - "$(basename "$SOURCE_OUTPUT_FILE_JSON")" | \
  openssl enc -aes-256-cbc -pass pass:"$BW_TAR_PASS" -out "$ARCHIVE_FILE"

# Remove raw JSON export after encryption
rm -f "$SOURCE_OUTPUT_FILE_JSON"

echo "$LOG_PREFIX ### Backup - End ###"

# ========================
# Restore / Import
# ========================
echo "$LOG_PREFIX ### Restore - Start ###"

# Switch to destination API keys
unset BW_CLIENTID
unset BW_CLIENTSECRET
export BW_CLIENTID="${BW_CLIENTID_DEST}"
export BW_CLIENTSECRET="${BW_CLIENTSECRET_DEST}"

DEST_EXPORT_OUTPUT_BASE="bw_vault_items_to_remove"
DEST_OUTPUT_FILE="$BACKUP_DIR/${DEST_EXPORT_OUTPUT_BASE}${TIMESTAMP}.json"

echo "$LOG_PREFIX Logging into Destination Bitwarden Server..."
bw logout 2>/dev/null || true
bw config server "$BW_SERVER_DEST"
bw login "$BW_ACCOUNT_DEST" --apikey --raw >/tmp/bw_apikey_dest.$$ 2>/dev/null || true
BW_SESSION_DEST=$(bw unlock "$BW_PASS_DEST" --raw)
echo "$BW_SESSION_DEST" >/tmp/bw_session_dest.$$
chmod 600 /tmp/bw_session_dest.$$

echo "$LOG_PREFIX Exporting current items from destination vault..."
bw --session "$BW_SESSION_DEST" export --format json --output "$DEST_OUTPUT_FILE"

folders_total=$(jq '.folders | length' "$DEST_OUTPUT_FILE" 2>/dev/null || echo 0)
items_total=$(jq '.items | length' "$DEST_OUTPUT_FILE" 2>/dev/null || echo 0)
attachments_total=$(jq '.attachments | length' "$DEST_OUTPUT_FILE" 2>/dev/null || echo 0)

echo "$LOG_PREFIX Destination vault contains $folders_total folders, $items_total items, $attachments_total attachments."

# ------------------------
# Function to delete items with progress (cron-friendly)
# ------------------------
delete_with_progress() {
  local type=$1
  local jqpath=$2
  local total=$3
  local deleted_count=0
  local failed_count=0

  if [ "$total" -eq 0 ]; then
    echo "$LOG_PREFIX No $type to delete."
    return 0
  fi

  echo "$LOG_PREFIX Preparing to delete $total $type..."

  # Disable 'exit on error' for jq/mapfile to avoid early termination
  set +e
  mapfile -t ids < <(jq -r "$jqpath" "$DEST_OUTPUT_FILE" 2>/dev/null)
  set -e

  for id in "${ids[@]}"; do
    [ -z "$id" ] || [ "$id" = "null" ] && continue

    if [ "$DRY_RUN" -eq 1 ]; then
      deleted_count=$((deleted_count + 1))
      continue
    fi

    if bw --session "$BW_SESSION_DEST" delete -p "$type" "$id" >/dev/null 2>&1; then
      deleted_count=$((deleted_count + 1))
    else
      failed_count=$((failed_count + 1))
    fi
    sleep "$RATE_LIMIT_DELAY"
  done

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "$LOG_PREFIX [DRY-RUN] $deleted_count $type would be deleted."
  else
    echo "$LOG_PREFIX Deleted $deleted_count/$total $type."
    [ "$failed_count" -gt 0 ] && echo "$LOG_PREFIX Warning: $failed_count $type failed to delete."
  fi
}


# Delete folders → items → attachments
delete_with_progress "folder" '.folders[]?.id' "$folders_total" || true
delete_with_progress "item"   '.items[]?.id'   "$items_total" || true
delete_with_progress "attachment" '.attachments[]?.id' "$attachments_total" || true

echo "$LOG_PREFIX Item deletion complete."
echo "$LOG_PREFIX Proceeding to restore/import stage..."
# ------------------------
# Restore latest backup
# ------------------------
DEST_LATEST_BACKUP_TAR=$(find "$BACKUP_DIR" -type f -name "bw_export_*.tar.gz.enc" -print0 | xargs -0 ls -1t 2>/dev/null | head -n1 || true)
[ -z "$DEST_LATEST_BACKUP_TAR" ] && { echo "$LOG_PREFIX Error: no backup archive found. Aborting."; exit 1; }

echo "$LOG_PREFIX Decrypting and extracting $DEST_LATEST_BACKUP_TAR..."
openssl enc -d -aes-256-cbc -pass pass:"$BW_TAR_PASS" -in "$DEST_LATEST_BACKUP_TAR" | tar -xz -C "$BACKUP_DIR"
echo "$LOG_PREFIX Extraction complete."

DEST_LATEST_BACKUP_JSON=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "bw_export_*.json" -print0 | xargs -0 ls -1t 2>/dev/null | head -n1 || true)
[ -z "$DEST_LATEST_BACKUP_JSON" ] && { echo "$LOG_PREFIX Error: no JSON backup found. Aborting."; exit 1; }

if [ "$DRY_RUN" -eq 1 ]; then
  echo "$LOG_PREFIX 🧪 DRY-RUN: No changes applied."
  echo "$LOG_PREFIX Would import JSON: $DEST_LATEST_BACKUP_JSON"
else
  echo "$LOG_PREFIX ✅ Importing backup into destination vault: $DEST_LATEST_BACKUP_JSON"
  bw --session "$BW_SESSION_DEST" import bitwardenjson "$DEST_LATEST_BACKUP_JSON"
fi

# Cleanup temporary files
rm -f "$DEST_OUTPUT_FILE" "$DEST_LATEST_BACKUP_JSON"
echo "$LOG_PREFIX ### Restore - End ###"

bw logout >/dev/null 2>&1 || true

# Unset sensitive variables
unset BW_CLIENTID BW_CLIENTSECRET BW_TAR_PASS
unset BW_ACCOUNT_SOURCE BW_PASS_SOURCE BW_CLIENTID_SOURCE BW_CLIENTSECRET_SOURCE BW_SERVER_SOURCE
unset BW_ACCOUNT_DEST BW_PASS_DEST BW_CLIENTSECRET_DEST BW_SERVER_DEST

# Final summary of actions
if [ "$DRY_RUN" -eq 1 ]; then
  echo "$LOG_PREFIX [DRY-RUN] Summary of what would be deleted/imported:"
else
  echo "$LOG_PREFIX Summary of deletions:"
  echo "$LOG_PREFIX Folders deleted: $folders_total"
  echo "$LOG_PREFIX Items deleted: $items_total"
  echo "$LOG_PREFIX Attachments deleted: $attachments_total"
fi

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo
echo "$LOG_PREFIX Bitwarden sync finished at $END_TIME"