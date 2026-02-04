log() {
  echo "[$(date -Is)] $*"
}

log "Starting bootstrap"

#!/usr/bin/env bash
set -euo pipefail

log "Constants definition"
BASE="/opt/ca-lab"
REPO_RAW="https://raw.githubusercontent.com/andrey-gamboa/LabCA/main"

log "Main folder structure built"
mkdir -p "$BASE/install" "$BASE/scripts" "$BASE/app"

log "Downloading installers"
# --- Download installers
curl -fsSL "$REPO_RAW/install/install-packages.sh"  -o "$BASE/install/install-packages.sh"
curl -fsSL "$REPO_RAW/install/install-app.sh"       -o "$BASE/install/install-app.sh"
curl -fsSL "$REPO_RAW/install/install-systemd.sh"  -o "$BASE/install/install-systemd.sh"
curl -fsSL "$REPO_RAW/install/install-apache.sh"   -o "$BASE/install/install-apache.sh"

log "Downloading scripts"
# --- Download PKI scripts
curl -fsSL "$REPO_RAW/scripts/init-pki.sh"   -o "$BASE/scripts/init-pki.sh"
curl -fsSL "$REPO_RAW/scripts/issue-cert.sh" -o "$BASE/scripts/issue-cert.sh"

log "Changing file permissions"
chmod +x $BASE/install/*.sh
chmod +x $BASE/scripts/*.sh

log "Executing Installers"
# --- Execute installers (order matters)
$BASE/install/install-packages.sh
$BASE/install/install-app.sh
$BASE/install/install-systemd.sh
$BASE/install/install-apache.sh

 systemctl restart apache2
echo "[BOOTSTRAP] Done"
