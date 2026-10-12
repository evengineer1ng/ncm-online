#!/usr/bin/env bash
# Install the ascent ring on NCM Online (run from the repo root on the dev machine):
#   * NCM Sky 0.2.3 (dist/ncm-sky-0.2.3.zip: DLL 0.2.2 unchanged, NcmSky.reds + ncm_sky.archive with ring kinds 10-14)
#     into the hosted mod store, and its declaration in server.jsonc
#   * ncm_world client/deep.lua (sends the ring) + server/deep.lua (ncm_deep_ring_z / ncm_deep_ring_far)
# Backs up everything it touches, restarts only if nobody is online, and waits for the boot.
# Usage: bash tools/deep/ops/install-ascent-ring.sh
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY=~/.ssh/id_ed25519
ZIP=dist/ncm-sky-0.2.3.zip
[ -f "$ZIP" ] || { echo "no $ZIP"; exit 1; }
SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)
SIZE=$(stat -c %s "$ZIP")
scp -i $KEY -q "$ZIP" $HOST:/tmp/ncm-sky-0.2.3.zip
scp -i $KEY -q ncm/online/resources/ncm_world/client/deep.lua $HOST:/tmp/ring-client-deep.lua
scp -i $KEY -q ncm/online/resources/ncm_world/server/deep.lua $HOST:/tmp/ring-server-deep.lua
ssh -i $KEY $HOST "SHA=$SHA SIZE=$SIZE bash -s" <<'REMOTE'
set -euo pipefail
S=/opt/ncm/server; W=/opt/ncm/resources/ncm/ncm_world; LOG=/opt/ncm/logs/server.log
T=$(date -u +%Y%m%dT%H%M%SZ)
[ "$(sha256sum /tmp/ncm-sky-0.2.3.zip | cut -d' ' -f1)" = "$SHA" ] || { echo "upload corrupted"; exit 1; }
last=$(grep -E "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not restarting"; exit 1;; esac
B=/opt/ncm/backups/pre-ascent-ring-$T; mkdir -p $B
cp $S/server.jsonc $B/; cp $W/client/deep.lua $B/client-deep.lua; cp $W/server/deep.lua $B/server-deep.lua
echo "backup $B"
sudo systemctl stop ncm-server
cp /tmp/ncm-sky-0.2.3.zip $S/.open77/mods/$SHA.blob
python3 - "$S" "$SHA" "$SIZE" <<'PY'
import json, re, sys, datetime
root, sha, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
old = json.load(open(f"{root}/.open77/mods/77837ed171d10fb70182542c17b63e999ed680cd0eb448f290dfb0e2c14122af.json"))
meta = dict(old, version="0.2.3", fileName="ncm-sky-0.2.3.zip", sha256=sha, sizeBytes=size,
            importedAtUtc=datetime.datetime.now(datetime.timezone.utc).isoformat())
json.dump(meta, open(f"{root}/.open77/mods/{sha}.json", "w"), indent=2)
p = f"{root}/server.jsonc"; t = open(p).read()
pat = re.compile(r'("id": "ncm-sky",\s*"source": "hosted",\s*"displayName": "NCM Sky",\s*)"version": "[^"]+",\s*"sha256": "[0-9a-f]+",\s*"sizeBytes": \d+')
t2, n = pat.subn(lambda m: m.group(1) + f'"version": "0.2.3",\n        "sha256": "{sha}",\n        "sizeBytes": {size}', t)
assert n == 1, "ncm-sky declaration not found exactly once"
open(p, "w").write(t2)
print("declared ncm-sky 0.2.3", sha[:12], size)
PY
cp /tmp/ring-client-deep.lua $W/client/deep.lua
cp /tmp/ring-server-deep.lua $W/server/deep.lua
sudo systemctl start ncm-server
echo "== restarted at $(date -u); waiting for the boot"
for i in $(seq 1 60); do
  if tail -n 400 $LOG | grep -q "BOOT driver"; then break; fi
  sleep 5
done
tail -n 800 $LOG | grep -E "ncm-sky|required mod|BOOT driver|SCRIPT ERROR|\[ERR\]" | tail -12 || true
REMOTE
echo "== done. Relaunch the game through the launcher (accept NCM Sky 0.2.3), then climb past 1.5 km."
