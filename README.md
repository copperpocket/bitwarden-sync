# Bitwarden Vault Sync Script

Automates backup/export from a source Bitwarden/Vaultwarden vault and restore/import to a destination vault.  

## Features

- Backup source vault to encrypted JSON archives.
- Remove existing items from destination vault before importing.
- Optional DRY_RUN mode for safe testing without modifying data.
- Logs all actions for auditing.
- Automatic cleanup of old backups and logs.

## Requirements

- Bash (tested on Linux)
- Bitwarden CLI (`bw`)
- `jq` (for JSON processing)
- `openssl`
- Access to source and destination Bitwarden API keys
- `.enc` password/key files for encrypting/decrypting archives

## Installation

1. Clone or copy the script to your server:
   ```bash
   git clone <repo_url>
   cd bitwarden-sync
2. Ensure .enc password/key files are present and accessible by the script.
3. Make the script executable:
   chmod +x bitwarden_sync.sh

## Usage

- Dry Run (simulate deletions/imports):
  DRY_RUN=1 ./bitwarden_sync.sh
- Perform Actual Sync:
  ./bitwarden_sync.sh
- Logs are stored in ./logs/ with timestamped filenames.

## Cron Example
0 3 * * * /path/to/bitwarden-sync/bitwarden_sync.sh
This will run the sync daily at 3 AM.

## Security
- Keep .enc key/password files private and secure.
- Do not commit sensitive files (logs, backups, .enc) to Git.

## License
MIT License