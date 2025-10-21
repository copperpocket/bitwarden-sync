# 🔐 Bitwarden Vault Sync

A lightweight Bash utility for automated, encrypted Bitwarden-to-Bitwarden (or Vaultwarden) vault synchronization.
Designed for backups, off-site mirroring, and disaster recovery automation — safely, cleanly, and repeatably.

## Requirements
- `Bash` (tested on Linux)
- Bitwarden CLI (`bw`)
- `jq` (for JSON processing)
- `openssl` for encryption
- Source and destination Bitwarden `API keys`
- Encrypted `.enc` key/password files

## 🧠 What It Does
- Exports all data from a source Bitwarden or Vaultwarden server.
- Encrypts the exported JSON archives with your .enc key files.
- Imports to a target vault.
- Cleans up old backups and logs automatically.
- Supports DRY_RUN for non-destructive testing.

## 🚀 Quick Start

#### 1. Install Bitwarden CLI
This script depends on the official [Bitwarden CLI](https://bitwarden.com/help/cli/)
```bash
sudo apt install jq openssl -y
curl -fsSL https://vault.bitwarden.com/download/?app=cli&platform=linux -o /usr/local/bin/bw
chmod +x /usr/local/bin/bw
```
> [!IMPORTANT]
> The CLI must be located at /usr/local/bin/bw or another directory in your PATH.
  If using cron, make sure /usr/local/bin is in PATH (cron uses a minimal environment).
  

#### 2. Test installation:
```bash
bw --version
```

#### 3. Clone and Prepare the Script
```bash
  git clone https://github.com/copperpocket/bitwarden-sync.git
  cd bitwarden-sync
  chmod +x bitwarden_sync.sh
```
#### 4. Ensure your encryption key/password files (.enc) are present and readable by the script:
```bash
  bitwarden-sync/
  ├── bitwarden_sync.sh
  ├── key.enc
  ├── pw.enc
  └── backups/
```

#### 5. Run a Manual Sync
Dry-run (safe test):
```bash
  DRY_RUN=1 ./bitwarden_sync.sh
```
Perform a full live sync:
```bash
  ./bitwarden_sync.sh
```
Logs are written to:
```bash
  /opt/bitwarden-sync/logs/
```
Backups are stored as:
```bash
  /opt/bitwarden-sync/backups/bw_export_YYYYMMDDHHMMSS.tar.gz.enc
```

## ⚙️ Cron Setup
Example: Run every 6 hours
```bash
  0 */6 * * * /opt/bitwarden-sync/bitwarden_sync.sh >> /opt/bitwarden-sync/bitwarden_sync.log 2>&1
```
#### 💡 Tip: Cron doesn’t load your shell environment.
If you get bw: command not found, ensure your script includes:
```bash
PATH=/usr/local/bin:/usr/bin:/bin
```



## 🔒 Security Notes
- Keep .enc files and logs private and out of version control.
- Never store master passwords or API tokens in plaintext.
- Verify file permissions on /opt/bitwarden-sync.

## License
- MIT License — free for personal or commercial use.
- Contributions and pull requests are welcome.