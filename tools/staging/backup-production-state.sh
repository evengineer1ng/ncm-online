#!/usr/bin/env bash
set -euo pipefail

# Protective snapshot before a production server/configuration change.
# Run on the host. No database password or row content is printed.

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="/opt/ncm/backups/pre-carrier-prod-${stamp}"

sudo install -d -m 0700 "$backup"

sudo mariadb-dump \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  --hex-blob \
  ncm \
  | gzip -9 \
  | sudo tee "$backup/ncm.sql.gz" >/dev/null

sudo chmod 0600 "$backup/ncm.sql.gz"
sudo gzip -t "$backup/ncm.sql.gz"

state=(server.jsonc)
for candidate in acl.jsonc tunables.json .open77; do
  if sudo test -e "/opt/ncm/server/$candidate"; then
    state+=("$candidate")
  fi
done

sudo tar \
  -C /opt/ncm/server \
  -czf "$backup/operator-state.tar.gz" \
  "${state[@]}"
sudo chmod 0600 "$backup/operator-state.tar.gz"
sudo tar -tzf "$backup/operator-state.tar.gz" >/dev/null

echo "BACKUP=$backup"
sudo sha256sum "$backup/ncm.sql.gz" "$backup/operator-state.tar.gz"
sudo stat -c '%n %s bytes mode=%a' "$backup/ncm.sql.gz" "$backup/operator-state.tar.gz"
echo "DB_TABLES"
sudo mariadb -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='ncm';"
