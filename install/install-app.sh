#!/usr/bin/env bash
set -euo pipefail

CA_USER="$(id -un 1000 2>/dev/null || echo labcauser)"
APP_BASE="/opt/ca-lab/app"

mkdir -p "/opt/ca-lab/app/ca-web"
chown -R "$CA_USER:$CA_USER" /opt/ca-lab

# Pull app source
curl https://raw.githubusercontent.com/andrey-gamboa/LabCA/main/app/ca-web/ca-web.csproj -o /opt/ca-lab/app/ca-web/ca-web.csproj

chown -R "$CA_USER:$CA_USER" "$APP_BASE"

sudo -u "$CA_USER" -H bash -lc "
  dotnet publish $APP_BASE/ca-web/ca-web.csproj \
    -c Release \
    -o $APP_BASE/ca-web/publish
"
