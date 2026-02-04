log() {
  echo "[$(date -Is)] $*"
}

log "Installing system packages testandrey"

#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/ca-lab"
REPO_RAW="https://raw.githubusercontent.com/andrey-gamboa/LabCA/main"

echo "[BOOTSTRAP] Starting LabCA bootstrap"

mkdir -p "$BASE/install" "$BASE/scripts" "$BASE/app"

# --- Download installers
curl -fsSL "$REPO_RAW/install/install-packages.sh"  -o "$BASE/install/install-packages.sh"
curl -fsSL "$REPO_RAW/install/install-app.sh"       -o "$BASE/install/install-app.sh"
curl -fsSL "$REPO_RAW/install/install-systemd.sh"  -o "$BASE/install/install-systemd.sh"
curl -fsSL "$REPO_RAW/install/install-apache.sh"   -o "$BASE/install/install-apache.sh"

# --- Download PKI scripts
curl -fsSL "$REPO_RAW/scripts/init-pki.sh"   -o "$BASE/scripts/init-pki.sh"
curl -fsSL "$REPO_RAW/scripts/issue-cert.sh" -o "$BASE/scripts/issue-cert.sh"

chmod +x $BASE/install/*.sh
chmod +x $BASE/scripts/*.sh

# --- Execute installers (order matters)
$BASE/install/install-packages.sh
$BASE/install/install-app.sh
$BASE/install/install-systemd.sh
$BASE/install/install-apache.sh

 systemctl restart apache2
echo "[BOOTSTRAP] Done"
