#!/usr/bin/env bash
# The flying AV to NCM Online (run from the repo root, with nobody online). One full restart (KB-460), everything at once:
#   * every NCM resource from git: the AV Enter prompt (F boards an AV), the Trauma Team AV catalogued as
#     Vehicle.av_zetatech_atlus (av_trauma never projected), engineering.flightcontrol (the FC-1 fly-by-wire), the VL-28
#     lift engine, the Atlus engine pods, the client's flight-computer frame, the server's jet fuel accounting
#   * NCM Carrier 0.1.39 (required mod): the wrench carries the Machine's mass and its angular acceleration, and an AV's
#     physics is switched on (ForceEnablePhysics) while its flight computer flies it
#   * the AV asset: record -> Vehicle.av_zetatech_atlus; its own tank 1,500 L (a car's 60 L is a minute of hover)
#   * the `av` kit by the ledgered owner grant (4x VL-28 on the pods, 2x FD-1, AC-6, PT-500, XLB-WH1, FC-1, full tanks)
# Backs up resources, tunables and every table it touches first.
# Usage: bash tools/deep/ops/install-av.sh [driver prefix]   (default: pellerino's driver 481c4984)
set -euo pipefail
HOST=ubuntu@52.60.225.137
KEY=~/.ssh/id_ed25519
DRV="${1:-481c4984}"
CARRIER=dist/ncm-carrier-0.1.39.zip
[ -f "$CARRIER" ] || { echo "missing $CARRIER (tools/build-carrier.ps1)"; exit 1; }
[ -z "$(git status --porcelain ncm/online/resources)" ] || { echo "uncommitted changes under ncm/online/resources: commit first"; exit 1; }
REV=$(git rev-parse --short HEAD)
TMP=$(mktemp -d)
git ls-files ncm/online/resources | sed 's#^ncm/online/resources/##' > "$TMP/list"
tar czf "$TMP/res.tgz" -C ncm/online/resources -T "$TMP/list"
scp -i $KEY -q "$TMP/res.tgz" $HOST:/tmp/res-av.tgz
scp -i $KEY -q "$CARRIER" tools/staging/publish-carrier.py $HOST:/tmp/
ssh -i $KEY $HOST "REV=$REV DRV=$DRV bash -s" <<'REMOTE'
set -euo pipefail
LOG=/opt/ncm/logs/server.log
TUN=/opt/ncm/server/tunables.json
T=$(date -u +%Y%m%dT%H%M%SZ)
last=$(grep -aE "\] connected: player=|disconnected: player=" $LOG | tail -1 || true)
case "$last" in *" connected: player="*) echo "a player looks online ($last); not deploying"; exit 1;; esac
AV=$(sudo mysql ncm -N -B -e "SELECT asset_id FROM vehicle_asset WHERE ncm_driver_id LIKE '${DRV}%' AND vehicle_key='zetatech_atlus_trauma' LIMIT 1")
[ -n "$AV" ] || { echo "driver ${DRV}* has no Atlus AV"; exit 1; }
B=/opt/ncm/backups/pre-av-$T; mkdir -p $B
tar czf $B/resources.tgz -C /opt/ncm/resources ncm
cp $TUN /opt/ncm/server/server.jsonc $B/
sudo mysqldump ncm vehicle_asset machine_fuel machine_configuration machine_configuration_current machine_configuration_item \
  component_asset component_asset_transfer component_operation component_state machine_control_binding owner_grant_ledger | gzip > $B/tables.sql.gz
echo "backup $B (git $REV) | AV ..${AV: -6}"
sudo systemctl stop ncm-server
tar xzf /tmp/res-av.tgz -C /opt/ncm/resources/ncm
cp /tmp/ncm-carrier-0.1.39.zip /opt/ncm/mods/
python3 /tmp/publish-carrier.py /opt/ncm/server --id ncm-carrier --display-name 'NCM Carrier' --zip /opt/ncm/mods/ncm-carrier-0.1.39.zip --version 0.1.39 --import-blob --enable | tail -2
sudo mysql ncm -e "UPDATE vehicle_asset SET record='Vehicle.av_zetatech_atlus' WHERE asset_id='$AV';
  INSERT INTO machine_fuel (asset_id, fuel_ml, capacity_ml, updated_at) VALUES ('$AV', 1500000, 1500000, UNIX_TIMESTAMP())
    ON DUPLICATE KEY UPDATE fuel_ml=1500000, capacity_ml=1500000, updated_at=UNIX_TIMESTAMP();
  SELECT asset_id, vehicle_key, record FROM vehicle_asset WHERE asset_id='$AV'; SELECT fuel_ml, capacity_ml FROM machine_fuel WHERE asset_id='$AV';"
SPEC="${DRV}|atlus|av#${T}"
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
  [ "$n" -ge 15 ] && break   # the kit line, its 13 items and the presence refresh
  tail -c 6000000 $LOG | grep -a "OWNER GRANT" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | grep -aq "REFUSED\|ignored\|skipped\|no driver" && break
done
sleep 3
tail -c 6000000 $LOG | grep -aE "Resource set published|Required mods|OWNER GRANT|SCRIPT ERROR|\[ERR\]|BOOT driver" | awk -v s="$START" '$1" "substr($2,1,8) >= s' | cut -c1-330 || true
python3 - "$TUN" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.get("resources", {}).get("ncm_world", {}).pop("ownerGrant", None)
json.dump(d, open(p, "w"), indent=2)
PY
grep -q ownerGrant $TUN && echo "WARNING: ownerGrant still in tunables.json" || echo "== ownerGrant removed (the ledger would refuse it again anyway)"
echo "== the AV's fit"
sudo mysql ncm -t -e "SELECT d.code, i.interface_id AS mount, i.install_json AS facing, s.propellant_kg AS store FROM machine_configuration_current x
  JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id JOIN component_asset a ON a.asset_id=i.component_asset_id
  JOIN component_design d ON d.design_id=a.design_id LEFT JOIN component_state s ON s.asset_id=a.asset_id
  WHERE x.machine_asset_id='$AV' AND d.family IN ('propulsor','attitude','tank','exotic_drive','avionics') ORDER BY i.interface_id;
  SELECT control_key, gesture, command FROM machine_control_binding WHERE machine_asset_id='$AV' ORDER BY control_key, gesture;"
echo "== done. Join, Machine Index -> CALL the Atlus Trauma Team AV, walk to it, F. Then: Space/R up, W/S A/D Q/E, C down."
REMOTE
