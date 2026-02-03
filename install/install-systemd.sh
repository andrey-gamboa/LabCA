#!/usr/bin/env bash
set -euo pipefail

cp /tmp/LabCA/systemd/ca-web.service /etc/systemd/system/ca-web.service

systemctl daemon-reload
systemctl enable --now ca-web
