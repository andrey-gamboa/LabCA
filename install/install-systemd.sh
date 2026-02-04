#!/usr/bin/env bash
set -euo pipefail

cp /opt/ca-lab/install/ca-web.service /etc/systemd/system/ca-web.service
systemctl daemon-reload
systemctl enable --now ca-web
