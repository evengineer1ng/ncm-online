#!/usr/bin/env bash
# KB-472: the FL-6 fusion lift drives to NCM Online (run from the repo root, with nobody online). One full restart:
#   * every NCM resource from git (the FL-6 design and the Atlus belly mounts are seeded at boot)
#   * the `av_lift` kit on the driver's Atlus by the ledgered owner grant (two FL-6s, both tanks topped up)
# The grant runs at ncm_world's start; an Atlus already has its configuration record, so the parts mount at once.
# Usage: KEY=~/.ssh/lightsail-ncm.pem bash tools/deep/ops/install-fl6.sh [driver prefix] [Atlus asset suffix]
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY="${KEY:-$HOME/.ssh/id_ed25519}"
DRV="${1:-72519ab3}"
AV="${2:-78a10cb7f609}"
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
git ls-files ncm/online/resources | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i "$KEY" -q "$TMP/res.tgz" $HOST:/tmp/res-fl6.tgz
ssh -i "$KEY" $HOST "REV=$REV DRV=$DRV AVS=$AV bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
TUN=/opt/ncm/server/tunables.json
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -aE "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
B=/opt/ncm/backups/pre-fl6-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
cp $TUN $B/
sudo mysqldump ncm machine_configuration machine_configuration_current machine_configuration_item component_asset component_state machine_fuel owner_grant_ledger | gzip > $B/tables.sql.gz
echo "backup $B (git $REV)"
sudo systemctl stop ncm-server
tar xzf /tmp/res-fl6.tgz -C /opt/ncm/resources/ncm
SPEC="${DRV}|${AVS}|av_lift#${T}"
python3 - "$TUN" "$SPEC" <<'PY'
import json, sys
p, spec = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d.setdefault("resources", {}).setdefault("ncm_world", {})["ownerGrant"] = spec
json.dump(d, open(p, "w"), indent=2)
print("ownerGrant =", spec)
PY
START=$(date -u +"%Y-%m-%d %H:%M:%S")
sudo systemctl start ncm-server
echo "== started at $START UTC; waiting for the grant"
for i in $(seq 1 40); do
  sleep 5
  tail -c 6000000 $LOG | grep -a "OWNER GRANT" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | grep -aq "presence\|REFUSED\|skipped\|ignored\|has no" && break
done
tail -c 6000000 $LOG | grep -aE "Resource set published|OWNER GRANT|seeded .* launch Designs|SCRIPT ERROR|\[ERR\]" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | cut -c90-330 || true
python3 - "$TUN" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.get("resources", {}).get("ncm_world", {}).pop("ownerGrant", None)
json.dump(d, open(p, "w"), indent=2)
PY
grep -q ownerGrant $TUN && echo "WARNING: ownerGrant still in tunables.json" || echo "== ownerGrant removed"
REMOTE
