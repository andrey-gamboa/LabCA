#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y \
  apache2 \
  easy-rsa \
  zip unzip \
  wget curl \
  ca-certificates gnupg

# .NET 8 for Ubuntu 24.04
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O /tmp/ms.deb
dpkg -i /tmp/ms.deb
rm /tmp/ms.deb

apt update
apt install -y dotnet-sdk-8.0
