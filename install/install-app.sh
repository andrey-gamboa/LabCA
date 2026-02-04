#!/usr/bin/env bash
set -Eeuo pipefail

CA_USER="$(id -un 1000 2>/dev/null || echo labcauser)"
APP_DIR="/opt/ca-lab/app/ca-web"
RAW_BASE="https://raw.githubusercontent.com/andrey-gamboa/LabCA/main/app/ca-web"

mkdir -p "$APP_DIR"
chown -R "$CA_USER:$CA_USER" /opt/ca-lab

# Download BOTH files (and fail if not reachable)
curl -fsSL "$RAW_BASE/ca-web.csproj" -o "$APP_DIR/ca-web.csproj"
curl -fsSL "$RAW_BASE/Program.cs"   -o "$APP_DIR/Program.cs"

# Sanity checks (prevent silent HTML / empty files)
grep -q "<Project" "$APP_DIR/ca-web.csproj" || { echo "Bad csproj downloaded"; exit 10; }
grep -q "WebApplication" "$APP_DIR/Program.cs" || { echo "Bad Program.cs downloaded"; exit 11; }

chown -R "$CA_USER:$CA_USER" "$APP_DIR"

sudo -u "$CA_USER" -H bash -lc \
"dotnet publish $APP_DIR/ca-web.csproj -c Release -o $APP_DIR/publish"
