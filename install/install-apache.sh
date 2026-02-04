#!/usr/bin/env bash
set -euo pipefail

a2enmod proxy proxy_http rewrite
cp /tmp/LabCA/apache/000-default.conf /etc/apache2/sites-available/000-default.conf
