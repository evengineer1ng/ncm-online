#!/usr/bin/env bash
# The AV that renders + the AV Enter prompt to NCM Online (run from the repo root, with nobody online):
#   * every NCM resource from git (catalogue: the Trauma Team AV is Vehicle.av_zetatech_atlus -- Vehicle.av_trauma never
#     projected on a client; av_board's one persistent hint)
#   * the one AV asset's stored record moves to the same record (vehicle_asset row backed up first)
# Full restart, never a Warden resource restart (KB-460).
# Usage: bash tools/deep/ops/install-av.sh
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY=~/.ssh/id_ed25519
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
git ls-files ncm/online/resources | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i $KEY -q "$TMP/res.tgz" $HOST:/tmp/res-av.tgz
ssh -i $KEY $HOST "REV=$REV bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -E "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
B=/opt/ncm/backups/pre-av-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
sudo mysqldump ncm vehicle_asset --where="record='Vehicle.av_trauma'" | gzip > $B/av_asset.sql.gz
echo "backup $B (git $REV)"
sudo systemctl stop ncm-server
tar xzf /tmp/res-av.tgz -C /opt/ncm/resources/ncm
sudo mysql ncm -e "UPDATE vehicle_asset SET record='Vehicle.av_zetatech_atlus' WHERE record='Vehicle.av_trauma'; SELECT asset_id, vehicle_key, record FROM vehicle_asset WHERE vehicle_key='zetatech_atlus_trauma';"
sudo systemctl start ncm-server
echo "== restarted at $(date -u); waiting for the boot"
for i in $(seq 1 72); do
  if tail -n 600 $LOG | grep -q "BOOT driver"; then break; fi
  sleep 5
done
tail -n 2500 $LOG | grep -E "Resource set published|Required mods|BOOT driver|SCRIPT ERROR|\[ERR\]" | tail -8 || true
echo "== done. Join, open the Machine Index, CALL the Atlus Trauma Team AV, walk to it, press F."
REMOTE
