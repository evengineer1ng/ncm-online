#!/usr/bin/env bash
# Install the NCM Earth Underlay package on NCM Online (run from the repo root on the dev machine).
# Usage: bash tools/deep/ops/install-underlay.sh
# Backs up the live resource, replaces dist/ncm-earth-underlay.zip + ncwe-export.json + open77.lua, restarts the server
# (only if nobody is online), and waits for the BOOT lines. Players then relaunch the game so the launcher reinstalls
# the required mod "ncm_earth_underlay-assets".
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY=~/.ssh/id_ed25519
SRC=ncm/online/resources/ncm_earth_underlay
ZIP=$SRC/dist/ncm-earth-underlay.zip
[ -f "$ZIP" ] || { echo "no $ZIP: export the NCWE project (ncm/ncwe/ncm_earth_underlay.ncwe) first"; exit 1; }
WANT=$(python -I -c "import json;print(json.load(open('$SRC/ncwe-export.json'))['sha256'])")
HAVE=$(sha256sum "$ZIP" | cut -d' ' -f1)
[ "$WANT" = "$HAVE" ] || { echo "zip sha $HAVE != ncwe-export.json $WANT"; exit 1; }
scp -i $KEY -q "$ZIP" $HOST:/tmp/ncm-earth-underlay.zip
scp -i $KEY -q "$SRC/ncwe-export.json" "$SRC/open77.lua" $HOST:/tmp/
ssh -i $KEY $HOST 'bash -s' <<'REMOTE'
set -euo pipefail
R=/opt/ncm/resources/ncm/ncm_earth_underlay
LOG=/opt/ncm/logs/server.log
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -E "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not restarting"; exit 1;; esac
mkdir -p ~/drives-backups
tar czf ~/drives-backups/underlay-$T.tgz -C /opt/ncm/resources/ncm ncm_earth_underlay
echo "backup ~/drives-backups/underlay-$T.tgz"
sudo systemctl stop ncm-server
cp /tmp/ncm-earth-underlay.zip $R/dist/ncm-earth-underlay.zip
cp /tmp/ncwe-export.json $R/ncwe-export.json
cp /tmp/open77.lua $R/open77.lua
sha256sum $R/dist/ncm-earth-underlay.zip
sudo systemctl start ncm-server
echo "== restarted at $(date -u); waiting for the boot"
for i in $(seq 1 60); do
  if tail -n 400 $LOG | grep -q "BOOT driver"; then break; fi
  sleep 5
done
tail -n 600 $LOG | grep -E "ncm_earth_underlay|BOOT driver|SCRIPT ERROR" || true
REMOTE
echo "== done. Relaunch the game through the launcher so it installs ncm_earth_underlay-assets 1.0.1."
