#!/usr/bin/env bash
# KB-469: the car-class Atlus to NCM Online (run from the repo root, with nobody online). One full restart:
#   * every NCM resource from git (pool/catalogue record Vehicle.ncm_atlus_av)
#   * NCM Carrier 0.1.42 (the AV writer flies a car-class body) and NCM AV 0.2.0 (archive + Vehicle.ncm_atlus_av)
#   * every stored Atlus (vehicle_key zetatech_atlus_trauma) moved to Vehicle.ncm_atlus_av
# Backs up resources, server.jsonc and vehicle_asset first.
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY="${KEY:-$HOME/.ssh/id_ed25519}"
CARRIER=dist/ncm-carrier-0.1.42.zip
AV=dist/ncm-av-0.2.0.zip
for f in "$CARRIER" "$AV"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
git ls-files ncm/online/resources | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i "$KEY" -q "$TMP/res.tgz" "$CARRIER" "$AV" tools/staging/publish-carrier.py $HOST:/tmp/
ssh -i "$KEY" $HOST "REV=$REV bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -aE "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
B=/opt/ncm/backups/pre-kb469-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
cp /opt/ncm/server/server.jsonc $B/
sudo mysqldump ncm vehicle_asset | gzip > $B/vehicle_asset.sql.gz
echo "backup $B (git $REV)"
sudo systemctl stop ncm-server
tar xzf /tmp/res.tgz -C /opt/ncm/resources/ncm
cp /tmp/ncm-carrier-0.1.42.zip /tmp/ncm-av-0.2.0.zip /opt/ncm/mods/
python3 /tmp/publish-carrier.py /opt/ncm/server --id ncm-carrier --display-name 'NCM Carrier' --zip /opt/ncm/mods/ncm-carrier-0.1.42.zip --version 0.1.42 --import-blob --enable | tail -1
python3 /tmp/publish-carrier.py /opt/ncm/server --id ncm-av --display-name 'NCM AV' --zip /opt/ncm/mods/ncm-av-0.2.0.zip --version 0.2.0 --import-blob --enable | tail -1
sudo mysql ncm -t -e "UPDATE vehicle_asset SET record='Vehicle.ncm_atlus_av' WHERE vehicle_key='zetatech_atlus_trauma';
  SELECT asset_id, ncm_driver_id, record FROM vehicle_asset WHERE vehicle_key='zetatech_atlus_trauma';"
START=$(date -u +"%Y-%m-%d %H:%M:%S")
sudo systemctl start ncm-server
echo "== started at $START UTC"
sleep 45
tail -c 6000000 $LOG | grep -aE "Resource set published|Required mods|SCRIPT ERROR|\[ERR\]" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | cut -c1-220 || true
python3 -c "
import json; d=json.load(open('/opt/ncm/server/server.jsonc'))
print([(p['id'], p['version']) for p in d['requiredMods']['packages'] if p['id'] in ('ncm-av', 'ncm-carrier')])"
REMOTE
