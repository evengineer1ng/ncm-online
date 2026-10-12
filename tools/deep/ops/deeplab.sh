#!/usr/bin/env bash
# Doc 58 -- the propulsion laboratory: put ONE drive on Alabino's Hella, by an owner-grant kit, with one restart.
#
#   ssh -i ~/.ssh/id_ed25519 ubuntu@52.60.225.137 'bash -s' < deeplab.sh <impulse|fusion|warp|alcubierre|jump|wormhole>
#
# What it does (the 2026-10-11 method, made one-shot):
#   1. backs up tunables.json and BOTH Deep presence rows (read-only proof of where the expeditions were)
#   2. sets ncm_world.ownerGrant = "70353cc8|hella|lab_<drive>#<UTC stamp>" and restarts the server
#   3. waits for the kit's OWNER GRANT / DEEP LAB lines and prints them
#   4. REMOVES ownerGrant (and even if it stayed, the grant ledger would never apply that spec again)
#   5. prints both cars' positions before and after (ASTRO lines), so nothing moved them
# Anyone online is dropped for about a minute by the restart.
set -euo pipefail
drive="${1:-}"
drv="${2:-70353cc8}"
veh="${3:-hella}"
case "$drive" in impulse|fusion|warp|alcubierre|jump|wormhole) ;; *)
  echo "usage: deeplab.sh <impulse|fusion|warp|alcubierre|jump|wormhole> [driver prefix] [vehicle]"; exit 2;; esac
ts=$(date -u +%Y%m%dT%H%M%SZ)
tun=/opt/ncm/server/tunables.json
log=/opt/ncm/logs/server.log
mkdir -p ~/deeplab-backups
cp "$tun" ~/deeplab-backups/tunables-$ts.json
sudo mysql ncm -N -B -e "SELECT driver_id, place, updated_at, state_json FROM ncm_presence WHERE place='deep'" > ~/deeplab-backups/presence-$ts.tsv
echo "== before: both expeditions"
tail -c 3000000 "$log" | grep -a "ASTRO " | tail -2 | cut -c1-260 || true
spec="$drv|$veh|lab_$drive#$ts"
python3 - "$tun" "$spec" <<'PY'
import json, sys
p, spec = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d.setdefault("resources", {}).setdefault("ncm_world", {})["ownerGrant"] = spec
json.dump(d, open(p, "w"), indent=2)
print("ownerGrant =", spec)
PY
start=$(date -u +"%Y-%m-%d %H:%M:%S")
sudo systemctl restart ncm-server
echo "== server restarting at $start UTC; waiting for the lab kit (up to 4 min)"
ok=0
for i in $(seq 1 48); do
  sleep 5
  if tail -c 5000000 "$log" | grep -a "DEEP LAB $drive applied" | grep -aq "$ts"; then ok=1; break; fi
  if tail -c 5000000 "$log" | grep -a "OWNER GRANT" | grep -aq "REFUSED\|ignored\|skipped"; then break; fi
done
sleep 2
echo "== the kit"
tail -c 5000000 "$log" | grep -a "OWNER GRANT\|DEEP LAB\|PRESENCE driver" | awk -v s="$start" '$1" "substr($2,1,8) >= s' | cut -c32-460 || true
# 4. never leave a grant behind
python3 - "$tun" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.get("resources", {}).get("ncm_world", {}).pop("ownerGrant", None)
json.dump(d, open(p, "w"), indent=2)
PY
grep -q ownerGrant "$tun" && echo "WARNING: ownerGrant still in tunables.json" || echo "== ownerGrant removed from tunables.json (no restart needed)"
echo "== the Hella's fit now"
sudo mysql ncm -t -e "SELECT d.code, i.interface_id AS mount, i.install_json AS facing, s.propellant_kg AS store FROM machine_configuration_current x
  JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id JOIN component_asset a ON a.asset_id=i.component_asset_id
  JOIN component_design d ON d.design_id=a.design_id LEFT JOIN component_state s ON s.asset_id=a.asset_id
  WHERE x.machine_asset_id LIKE '%560c94' AND d.family IN ('propulsor','impulse_actuator','attitude','tank','exotic_drive');
  SELECT b.control_key, b.gesture, d.code, b.command FROM machine_control_binding b JOIN component_asset a ON a.asset_id=b.component_asset_id
  JOIN component_design d ON d.design_id=a.design_id WHERE b.machine_asset_id LIKE '%560c94' ORDER BY b.control_key, b.gesture;"
echo "== after: both expeditions (waiting for the first ASTRO lines)"
for i in $(seq 1 24); do
  sleep 5
  n=$(tail -c 3000000 "$log" | awk -v s="$start" '$1" "substr($2,1,8) >= s' | sed -n '/BOOT driver/,$p' | grep -ac "ASTRO " || true)
  [ "$n" -ge 2 ] && break
done
tail -c 3000000 "$log" | grep -a "ASTRO " | awk -v s="$start" '$1" "substr($2,1,8) >= s' | tail -2 | cut -c1-260 || true
[ "$ok" = 1 ] && echo "== DEEP LAB $drive ready on the Hella. Join as Alabino; Triangle drives ONLY the $drive." || echo "== the kit did not report ready: read the OWNER GRANT lines above"
echo "backups: ~/deeplab-backups/*-$ts.*"
