#!/usr/bin/env bash
# KB-465/KB-466 + the collapse going live, to NCM Online (run from the repo root, with nobody online). One full restart:
#   * every NCM resource from git: aerial machines out of ground races (KB-465), Space climbs the AV again (KB-466),
#     the collapse's `ncm_week_collapse_live_from` guard
#   * convars: ncm_week_collapse = live, ncm_week_collapse_live_from = 4 (owner 2026-10-13: "live from next reset only")
#   * a Trauma Team AV (Vehicle.av_zetatech_atlus) minted to the driver, its own 1,500 L tank, and the `av` kit fitted by
#     the ledgered owner grant (as install-av.sh did for pellerino)
# Backs up resources, server.jsonc, tunables and every table it touches first.
# Usage: bash tools/deep/ops/install-kb465.sh [driver prefix]   (default: easporks, 72519ab3)
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY=~/.ssh/lightsail-ncm.pem
DRV="${1:-72519ab3}"
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
git ls-files ncm/online/resources | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i $KEY -q "$TMP/res.tgz" $HOST:/tmp/res-kb465.tgz
ssh -i $KEY $HOST "REV=$REV DRV=$DRV bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
TUN=/opt/ncm/server/tunables.json
CFG=/opt/ncm/server/server.jsonc
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -aE "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
FULL=$(sudo mysql ncm -N -B -e "SELECT ncm_driver_id FROM ncm_driver WHERE ncm_driver_id LIKE '${DRV}%'")
[ "$(echo "$FULL" | grep -c .)" = 1 ] || { echo "driver ${DRV}* is not exactly one driver: $FULL"; exit 1; }
B=/opt/ncm/backups/pre-kb465-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
cp $TUN $CFG $B/
sudo mysqldump ncm vehicle_asset machine_fuel machine_configuration machine_configuration_current machine_configuration_item \
  component_asset component_asset_transfer component_operation component_state machine_control_binding owner_grant_ledger | gzip > $B/tables.sql.gz
echo "backup $B (git $REV) | driver ..${FULL: -6}"
python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except ValueError as e:
    sys.exit("server.jsonc is not plain JSON (comments?): %s -- set the two convars by hand; nothing changed" % e)
cv = d.setdefault("convars", {})
cv["ncm_week_collapse"] = "live"
cv["ncm_week_collapse_live_from"] = "4"
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
print("convars =", cv)
PY
sudo systemctl stop ncm-server
tar xzf /tmp/res-kb465.tgz -C /opt/ncm/resources/ncm
AV=$(sudo mysql ncm -N -B -e "SELECT asset_id FROM vehicle_asset WHERE server_id='ncm-dev' AND ncm_driver_id='$FULL' AND vehicle_key='zetatech_atlus_trauma' LIMIT 1")
if [ -z "$AV" ]; then
  AV=$(python3 -c "import uuid; print(uuid.uuid4())")
  sudo mysql ncm -e "INSERT INTO vehicle_asset (asset_id, server_id, ncm_driver_id, vehicle_key, record, class, acquired_via, granted_by, acquired_at,
      paint_primary, paint_secondary, origin, produced_at, lifecycle, odometer_m, gearbox_kind, gearbox_spec, gearbox_source, gearbox_at)
    VALUES ('$AV', 'ncm-dev', '$FULL', 'zetatech_atlus_trauma', 'Vehicle.av_zetatech_atlus', 'Tech', 'seed', 'console', UNIX_TIMESTAMP(),
      '#26282D', '#26282D', 'grant', UNIX_TIMESTAMP(), 'active', 0, 'automatic', 'a', 'factory', UNIX_TIMESTAMP())"
  echo "minted AV $AV"
else
  echo "driver already has AV $AV"
fi
sudo mysql ncm -e "INSERT INTO machine_fuel (asset_id, fuel_ml, capacity_ml, updated_at) VALUES ('$AV', 1500000, 1500000, UNIX_TIMESTAMP())
    ON DUPLICATE KEY UPDATE fuel_ml=1500000, capacity_ml=1500000, updated_at=UNIX_TIMESTAMP();
  SELECT asset_id, ncm_driver_id, vehicle_key, record FROM vehicle_asset WHERE asset_id='$AV'"
SPEC="${FULL:0:8}|${AV: -12}|av#${T}"
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
echo "== started at $START UTC; waiting for the boot and the kit"
for i in $(seq 1 60); do
  sleep 5
  n=$(tail -c 6000000 $LOG | grep -a "OWNER GRANT" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | wc -l)
  [ "$n" -ge 15 ] && break
  tail -c 6000000 $LOG | grep -a "OWNER GRANT" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | grep -aq "REFUSED\|ignored\|skipped\|no driver\|has no" && break
done
sleep 3
tail -c 6000000 $LOG | grep -aE "Resource set published|Required mods|OWNER GRANT|collapse\] ready|SCRIPT ERROR|\[ERR\]|environment" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | cut -c1-330 || true
python3 - "$TUN" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.get("resources", {}).get("ncm_world", {}).pop("ownerGrant", None)
json.dump(d, open(p, "w"), indent=2)
PY
grep -q ownerGrant $TUN && echo "WARNING: ownerGrant still in tunables.json" || echo "== ownerGrant removed (the ledger would refuse it again anyway)"
echo "== the AV's fit"
sudo mysql ncm -t -e "SELECT d.code, i.interface_id AS mount FROM machine_configuration_current x
  JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id JOIN component_asset a ON a.asset_id=i.component_asset_id
  JOIN component_design d ON d.design_id=a.design_id WHERE x.machine_asset_id='$AV' ORDER BY i.interface_id;"
REMOTE
