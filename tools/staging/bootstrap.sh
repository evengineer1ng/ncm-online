#!/usr/bin/env bash
# NCM staging server bootstrap (Ubuntu 24.04, Lightsail). Idempotent; run as the ubuntu user with sudo.
# Layout: /opt/ncm/server (OPEN//77 package), /opt/ncm/resources/ncm (our resources, synced by deploy-staging.ps1).
set -euo pipefail

PKG="${1:-/tmp/open77-server.tar.gz}"
DB_PASS_FILE="${2:-/tmp/ncm-db-pass}"

echo "== apt"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libicu74 libssl3 libstdc++6 zlib1g mariadb-server unzip curl > /dev/null

echo "== layout"
sudo mkdir -p /opt/ncm/server /opt/ncm/resources/ncm /opt/ncm/mods /opt/ncm/logs
sudo chown -R ubuntu:ubuntu /opt/ncm

echo "== server package"
if [ ! -x /opt/ncm/server/Open77.Server ]; then
  tar -xzf "$PKG" -C /opt/ncm/server
  chmod +x /opt/ncm/server/Open77.Server /opt/ncm/server/start.sh
fi
# our resources live outside the package tree and are linked in, like the Windows junction
ln -sfn /opt/ncm/resources/ncm /opt/ncm/server/resources/ncm
/opt/ncm/server/Open77.Server --version 2>/dev/null | head -1 || true

echo "== mariadb"
sudo systemctl enable --now mariadb > /dev/null
if [ -f "$DB_PASS_FILE" ]; then
  DBP="$(cat "$DB_PASS_FILE")"
  sudo mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ncm CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'ncm'@'127.0.0.1' IDENTIFIED BY '${DBP}';
ALTER USER 'ncm'@'127.0.0.1' IDENTIFIED BY '${DBP}';
GRANT ALL PRIVILEGES ON ncm.* TO 'ncm'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
  shred -u "$DB_PASS_FILE" 2>/dev/null || rm -f "$DB_PASS_FILE"
  echo "db user ncm@127.0.0.1 ready"
else
  echo "db password file missing; skipping user creation"
fi

echo "== systemd unit"
sudo tee /etc/systemd/system/ncm-server.service > /dev/null <<'UNIT'
[Unit]
Description=NCM Online (OPEN//77 dedicated server)
After=network-online.target mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/ncm/server
EnvironmentFile=-/opt/ncm/server.env
ExecStart=/opt/ncm/server/Open77.Server
Restart=always          # a clean shutdown from Warden (quit/restart) comes straight back
RestartSec=5
StandardOutput=append:/opt/ncm/logs/server.log
StandardError=append:/opt/ncm/logs/server.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable ncm-server > /dev/null

echo "== firewall (ufw)"
sudo ufw allow 22/tcp > /dev/null
sudo ufw allow 11778/udp > /dev/null
sudo ufw allow 11779/tcp > /dev/null
sudo ufw --force enable > /dev/null
sudo ufw status | sed -n 1,8p

echo "== done"
ls /opt/ncm/server | head -5
