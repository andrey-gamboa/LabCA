#!/usr/bin/env bash
set -euo pipefail

CA_USER="$(id -un 1000 2>/dev/null || echo labcauser)"
APP_BASE="/opt/ca-lab/app"
REPO_RAW="https://raw.githubusercontent.com/andrey-gamboa/LabCA/main"

mkdir -p "$APP_BASE"
chown -R "$CA_USER:$CA_USER" /opt/ca-lab

# Pull app source
rm -rf "$APP_BASE/ca-web"
curl -fsSL "$REPO_RAW/ca-web/ca-web.csproj"  -o "$APP_BASE/ca-web/ca-web.csproj"

chown -R "$CA_USER:$CA_USER" "$APP_BASE"

sudo -u "$CA_USER" -H bash -lc "
  dotnet publish $APP_BASE/ca-web/ca-web.csproj \
    -c Release \
    -o $APP_BASE/ca-web/publish
"
