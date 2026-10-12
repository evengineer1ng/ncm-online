#!/usr/bin/env bash
# L367 to NCM Online (run from the repo root on the dev machine, with nobody online):
#   * every NCM resource from git (overlaid on live; live-only assets such as fetched textures and radio data are kept)
#     incl. the new ncm_audio and ncm_build_kit, the underlay v3 package and migration 081
#   * required mods: NCM Audio 0.1.0 (new) and NCM Sky 0.2.4 (kit kinds, attached mode, KB-458 Earth yaw)
# Backs up the live resources, server.jsonc and the tables migration 081 touches, restarts, waits for the boot.
# Usage: bash tools/deep/ops/install-l367.sh
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY=~/.ssh/id_ed25519
SKY=dist/ncm-sky-0.2.4.zip
AUDIO=dist/ncm-audio-0.1.0.zip
for f in "$SKY" "$AUDIO" ncm/online/resources/ncm_build_kit/dist/ncm-build-kit.zip ncm/online/resources/ncm_earth_underlay/dist/ncm-earth-underlay.zip; do
  [ -f "$f" ] || { echo "missing $f (build it first: tools/build-sky.ps1, tools/build-audio.ps1, NCWE export)"; exit 1; }
done
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
{ git ls-files ncm/online/resources; echo ncm/online/resources/ncm_build_kit/dist/ncm-build-kit.zip;
  echo ncm/online/resources/ncm_earth_underlay/dist/ncm-earth-underlay.zip; } | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i $KEY -q "$TMP/res.tgz" "$SKY" "$AUDIO" tools/staging/publish-carrier.py $HOST:/tmp/
ssh -i $KEY $HOST "REV=$REV bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -E "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
B=/opt/ncm/backups/pre-l367-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
cp /opt/ncm/server/server.jsonc $B/
sudo mysqldump ncm market_inventory vehicle_asset component_asset exchange_post exchange_bid exchange_reservation vehicle_asset_transfer | gzip > $B/tables.sql.gz
echo "backup $B (git $REV)"
sudo systemctl stop ncm-server
tar xzf /tmp/res.tgz -C /opt/ncm/resources/ncm
cp /tmp/ncm-sky-0.2.4.zip /tmp/ncm-audio-0.1.0.zip /opt/ncm/mods/
python3 /tmp/publish-carrier.py /opt/ncm/server --id ncm-sky --display-name 'NCM Sky' --zip /opt/ncm/mods/ncm-sky-0.2.4.zip --version 0.2.4 --import-blob --enable | tail -2
python3 /tmp/publish-carrier.py /opt/ncm/server --id ncm-audio --display-name 'NCM Audio' --zip /opt/ncm/mods/ncm-audio-0.1.0.zip --version 0.1.0 --import-blob --enable | tail -2
sudo systemctl start ncm-server
echo "== restarted at $(date -u); waiting for the boot"
for i in $(seq 1 72); do
  if tail -n 600 $LOG | grep -q "BOOT driver"; then break; fi
  sleep 5
done
tail -n 2500 $LOG | grep -E "Required mods|migration|081|line-up for Week|ncm_build_kit|ncm_audio|BOOT driver|SCRIPT ERROR|\[ERR\]" | tail -20 || true
REMOTE
rm -rf "$TMP"
echo "== done. Relaunch through the launcher (accept NCM Audio, NCM Sky 0.2.4, the Build kit, the underlay) and walk MASTER_TEST §FX, §BLD7, §MKT, §SKY10."
