#!/usr/bin/env bash
# Every NCM resource from git to NCM Online, with one FULL restart (KB-460: never a Warden resource restart for a client
# change). Nothing else: no required mods, no grants, no database writes. Run from the repo root with nobody online.
# Usage: bash tools/deep/ops/install-resources.sh [dist/ncm-carrier-X.Y.Z.zip]   (optional: also publish that NCM Carrier)
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY="${KEY:-$HOME/.ssh/id_ed25519}"
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
git ls-files ncm/online/resources | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i $KEY -q "$TMP/res.tgz" $HOST:/tmp/res-only.tgz
CARRIER="${1:-}"
CVER=""
if [ -n "$CARRIER" ]; then
  [ -f "$CARRIER" ] || { echo "missing $CARRIER"; exit 1; }
  CVER=$(basename "$CARRIER" .zip | sed 's/^ncm-carrier-//')
  scp -i $KEY -q "$CARRIER" tools/staging/publish-carrier.py $HOST:/tmp/
fi
ssh -i $KEY $HOST "REV=$REV CVER=$CVER bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -aE "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
B=/opt/ncm/backups/pre-res-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
echo "backup $B (git $REV)"
sudo systemctl stop ncm-server
tar xzf /tmp/res-only.tgz -C /opt/ncm/resources/ncm
if [ -n "$CVER" ]; then
  cp /tmp/ncm-carrier-$CVER.zip /opt/ncm/mods/
  python3 /tmp/publish-carrier.py /opt/ncm/server --id ncm-carrier --display-name 'NCM Carrier' --zip /opt/ncm/mods/ncm-carrier-$CVER.zip --version $CVER --import-blob --enable | tail -2
fi
START=$(date -u +"%Y-%m-%d %H:%M:%S")
sudo systemctl start ncm-server
echo "== restarted at $START UTC; waiting for the boot"
for i in $(seq 1 60); do
  sleep 5
  tail -c 4000000 $LOG | grep -a "BOOT driver" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | grep -q . && break
done
tail -c 6000000 $LOG | grep -aE "Resource set published|Required mods|SCRIPT ERROR|\[ERR\]|BOOT driver" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | cut -c1-300 || true
echo "== done (git $REV). Relaunch through the launcher."
REMOTE
