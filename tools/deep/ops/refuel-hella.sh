#!/usr/bin/env bash
# Put back the Hella's ordinary (attitude) fuel the AC-6 burned fighting the grant-caused spin: 13.5 kg = 18,121 ml at
# Install.FUEL_KG_PER_L 0.745. Machine fuel (machine_fuel) + the flight record (fuelKg, dyn.tanks). Server stopped meanwhile.
set -euo pipefail
ts=$(date -u +%Y%m%dT%H%M%SZ)
asset=3be4c57f-5bac-43ae-8a37-16cca8560c94
driver=70353cc8-7fbc-4148-81c5-37d8cebbda69
sudo systemctl stop ncm-server
sudo mysql ncm -N -B -e "SELECT fuel_ml FROM machine_fuel WHERE asset_id='$asset'" > ~/hella-fuel-before-$ts.txt
sudo mysql ncm -e "UPDATE machine_fuel SET fuel_ml=18121, updated_at=UNIX_TIMESTAMP() WHERE asset_id='$asset'"
sudo mysql ncm -N -B -e "SELECT state_json FROM ncm_presence WHERE driver_id='$driver'" > ~/hella-presence-$ts.json
python3 - ~/hella-presence-$ts.json <<'PY' > ~/hella-presence-fuel.b64
import base64, json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
s["fuelKg"] = 13.5
d = s.setdefault("dyn", {})
t = d.get("tanks") or [0]
t[0] = 13.5          # the Machine's own tank (the only entry: fusion lives in the PT-500 device)
d["tanks"] = t
print(base64.b64encode(json.dumps(s, separators=(",", ":")).encode()).decode())
PY
sudo mysql ncm -e "UPDATE ncm_presence SET state_json=FROM_BASE64('$(cat ~/hella-presence-fuel.b64)') WHERE driver_id='$driver'"
sudo systemctl start ncm-server
echo "fuel before: $(cat ~/hella-fuel-before-$ts.txt) ml"
sudo mysql ncm -e "SELECT fuel_ml, ROUND(fuel_ml/1000*0.745,2) AS kg FROM machine_fuel WHERE asset_id='$asset'"
sudo mysql ncm -N -B -e "SELECT state_json FROM ncm_presence WHERE driver_id='$driver'" | python3 -c "import json,sys;s=json.loads(sys.stdin.read());print('record fuelKg',s.get('fuelKg'),'tanks',s['dyn']['tanks'])"
echo "server restarted; backups ~/hella-fuel-before-$ts.txt ~/hella-presence-$ts.json"
