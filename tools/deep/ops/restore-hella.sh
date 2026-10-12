#!/usr/bin/env bash
# One-time restore of evengam1ng's Hella (..560c94) to its pre-grant layout (2026-10-11 21:56 UTC snapshot):
#   FD-1 (..aba80e) underside facing down, bound hold-Y throttle | PT-500 (..f8b7d5) rear facing left | AC-6 (..798a3e)
#   roof facing up | IA-10 to storage (displaced by the FD-1) | fusion in the PT-500 = 308 kg.
# Runs while the server is stopped (nobody in the car: the engineering park check passes), then removes the grant.
set -euo pipefail
ts=$(date -u +%Y%m%dT%H%M%SZ)
eng=/opt/ncm/resources/ncm/ncm_world/server/engineering.lua
tun=/opt/ncm/server/tunables.json
mkdir -p ~/substrate-backups
cp "$eng" ~/substrate-backups/engineering-$ts.lua
cp "$tun" ~/substrate-backups/tunables-$ts.json

# 1. the `restore` kit (added once; refit = move a part that is elsewhere)
python3 - "$eng" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
if "restore = {" not in t:
    anchor = "    climb = {"
    assert t.count(anchor) == 1, "climb kit anchor not found"
    kit = '''    -- 2026-10-11 (owner): the Hella as it flew before the leftover `flight` grant moved its parts at restarts
    restore = {
        { code = "ZTC-FD1", mount = "mount.underside", facing = "down", bind = { "triangle", "hold", "throttle" }, refit = true },
        { code = "ZTC-PT500", mount = "mount.rear", facing = "left", refit = true },
        { code = "ZTC-AC6", mount = "mount.roof", facing = "up", refit = true },
    },
'''
    t = t.replace(anchor, kit + anchor)
    open(p, "w", encoding="utf-8").write(t)
    print("restore kit added")
else:
    print("restore kit already present")
PY

# 2. stop the server; fusion to 308 kg (the tank's own state and the flight record's carried tanks)
sudo systemctl stop ncm-server
sudo mysql ncm -e "UPDATE component_state SET propellant_kg=308 WHERE asset_id='4f0a42ea-c1ad-4c94-932c-9c8b75f8b7d5'; SELECT asset_id, propellant_kg FROM component_state WHERE asset_id='4f0a42ea-c1ad-4c94-932c-9c8b75f8b7d5';"
sudo mysql ncm -N -B -e "SELECT state_json FROM ncm_presence WHERE driver_id='70353cc8-7fbc-4148-81c5-37d8cebbda69'" > ~/hella-presence-$ts.json
python3 - ~/hella-presence-$ts.json <<'PY' > ~/hella-presence-new.b64
import base64, json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
tanks = (s.get("dyn") or {}).get("tanks") or []
i = max(range(len(tanks)), key=lambda k: float(tanks[k] or 0)) if tanks else None
if i is not None and 300 < float(tanks[i]) < 320:
    print("fusion tank", tanks[i], "-> 308", file=sys.stderr)
    tanks[i] = 308.0
else:
    print("no fusion tank entry near 308 found; record unchanged", file=sys.stderr)
print(base64.b64encode(json.dumps(s, separators=(",", ":")).encode()).decode())
PY
sudo mysql ncm -e "UPDATE ncm_presence SET state_json=FROM_BASE64('$(cat ~/hella-presence-new.b64)') WHERE driver_id='70353cc8-7fbc-4148-81c5-37d8cebbda69'"

# 3. the grant, once
python3 -c "import json;p='$tun';d=json.load(open(p));d['resources']['ncm_world']['ownerGrant']='70353cc8|hella|restore';json.dump(d,open(p,'w'),indent=2)"
sudo systemctl start ncm-server
echo "server starting; waiting for the grant..."
for i in $(seq 1 60); do
  n=$(tail -c 2000000 /opt/ncm/logs/server.log | grep -a "OWNER GRANT" | grep -ac "restore\|ZTC-\|ARC-" || true)
  tail -c 2000000 /opt/ncm/logs/server.log | grep -aq "OWNER GRANT kit restore" && sleep 6 && break
  sleep 5
done
tail -c 2000000 /opt/ncm/logs/server.log | grep -a "OWNER GRANT" | tail -4 | cut -c96-400

# 4. the grant, never again
python3 -c "import json;p='$tun';d=json.load(open(p));d['resources']['ncm_world'].pop('ownerGrant',None);json.dump(d,open(p,'w'),indent=2)"
grep -q ownerGrant "$tun" && echo "WARNING: ownerGrant still present" || echo "ownerGrant removed"
sudo mysql ncm -e "SELECT asset_id, propellant_kg FROM component_state WHERE asset_id='4f0a42ea-c1ad-4c94-932c-9c8b75f8b7d5';"
echo "backups: ~/substrate-backups/*-$ts.*, ~/hella-presence-$ts.json"
