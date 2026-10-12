#!/usr/bin/env python3
"""Doc 58: package the experimental-propulsion deploy for NCM Online.

Contents: every ncm_world file this work changed or added (against the live snapshot of 2026-10-12, base_ncm_world_20261012),
ncm_league's schema 080 + its manifest line, and the engineering core (installation.lua, systems.lua: the lab designs and
the drive commands) for every other resource that carries an identical copy. The installer REFUSES if any live file it
would replace changed since the snapshot (the live tree is ahead of the repo; never overwrite unseen work), backs up every
file it replaces, snapshots both Deep presence rows, restarts, and checks the boot and both expeditions' positions.
Output: dist/drives-deploy.tgz"""
import hashlib, io, os, tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.environ.get("DRIVES_BASE") or os.path.join(ROOT, "base_ncm_world_20261012")
WORLD = os.path.join(ROOT, "ncm_world")
LEAGUE = os.path.join(ROOT, "ncm_league")
OTHERS = ["ncm_aero", "ncm_build", "ncm_engineering", "ncm_league", "ncm_observer", "ncm_paddock", "ncm_scanner",
          "ncm_slipstream", "ncm_space", "ncm_speed", "ncm_workshop"]
CORE_SHARED = ["shared/core/engineering/installation.lua", "shared/core/engineering/systems.lua"]

def sha(b): return hashlib.sha256(b).hexdigest()

changed, added, base = [], [], []
for dirpath, _, names in os.walk(WORLD):
    for n in names:
        p = os.path.join(dirpath, n)
        rel = os.path.relpath(p, WORLD).replace(os.sep, "/")
        data = open(p, "rb").read()
        b = os.path.join(BASE, rel)
        if os.path.exists(b):
            old = open(b, "rb").read()
            if old != data:
                changed.append(("ncm_world/" + rel, p)); base.append((sha(old), "ncm_world/" + rel))
        else:
            added.append(("ncm_world/" + rel, p))
# ncm_league: the manifest (against the live copy pulled with it) and the new schema -- first deploy only
if not os.environ.get("DRIVES_SKIP_LEAGUE"):
    lm_live = open(os.path.join(LEAGUE, "open77.lua.live"), "rb").read()
    changed.append(("ncm_league/open77.lua", os.path.join(LEAGUE, "open77.lua"))); base.append((sha(lm_live), "ncm_league/open77.lua"))
    added.append(("ncm_league/server/schema/080_deep_drives.lua", os.path.join(LEAGUE, "server", "schema", "080_deep_drives.lua")))
# extra files: DRIVES_EXTRA="res/path/file.lua,..." with the pulled live copy beside the edited one as <file>.live
for rel in [x for x in (os.environ.get("DRIVES_EXTRA") or "").split(",") if x]:
    src = os.path.join(ROOT, rel)
    old = open(src + ".live", "rb").read()
    changed.append((rel, src)); base.append((sha(old), rel))
# the engineering core everywhere else (identical copies today: the installer checks each against the same base)
for res in OTHERS:
    for rel in CORE_SHARED:
        old = open(os.path.join(BASE, rel), "rb").read()
        changed.append((res + "/" + rel, os.path.join(WORLD, rel))); base.append((sha(old), res + "/" + rel))

install = r"""#!/usr/bin/env bash
# Doc 58 deploy: the experimental propulsion stable on NCM Online. Refuses over any live file that changed since the
# 2026-10-12 snapshot; backs up every replaced file; snapshots both Deep presence rows; restarts; checks the boot and
# that both expeditions are where the physics says (ASTRO lines before / after).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
res=/opt/ncm/resources/ncm
log=/opt/ncm/logs/server.log
cd "$res"
if ! sha256sum --quiet -c "$here/base.sha256"; then echo "REFUSED: a live file changed since the snapshot (nothing installed)"; exit 1; fi
for f in $(cd "$here/files" && find . -type f | sed 's#^\./##'); do
  if [ -e "$res/$f" ] && ! grep -q "  $f\$" "$here/base.sha256"; then echo "REFUSED: $f exists live but is not in the base list"; exit 1; fi
done
ts=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p ~/drives-backups
(cd "$res" && tar -czf ~/drives-backups/replaced-$ts.tgz $(cut -c67- "$here/base.sha256"))
sudo mysql ncm -N -B -e "SELECT driver_id, place, updated_at, state_json FROM ncm_presence WHERE place='deep'" > ~/drives-backups/presence-$ts.tsv
echo "== before"
tail -c 3000000 "$log" | grep -a "ASTRO " | tail -2 | cut -c1-260 || true
grep -q ownerGrant /opt/ncm/server/tunables.json && { echo "REFUSED: an ownerGrant is set in tunables.json -- remove it first"; exit 1; } || true
start=$(date -u +"%Y-%m-%d %H:%M:%S")
sudo systemctl stop ncm-server
cp -r "$here/files/." "$res/"
sudo systemctl start ncm-server
echo "== installed __N__ files at $start UTC (backup ~/drives-backups/replaced-$ts.tgz); waiting for the boot"
for i in $(seq 1 60); do
  sleep 5
  n=$(tail -c 8000000 "$log" | awk -v s="$start" '$1" "substr($2,1,8) >= s' | sed -n '/BOOT driver/,$p' | grep -ac "ASTRO " || true)
  [ "${n:-0}" -ge 2 ] && break
done
since() { tail -c 12000000 "$log" | awk -v s="$start" '$1" "substr($2,1,8) >= s'; }
echo "== boot"
since | grep -a "migration 080\|no pending migrations\|engineering designs ready\|BOOT driver\|catalogue ready\|BOOT [0-9]* presence" | cut -c1-240 || true
echo "== errors since the restart (expect none)"
since | grep -ai "script error\|error loading\|attempt to\|stack traceback\|FAILED" | grep -av "deviation" | head -20 | cut -c1-300 || true
echo "== after"
since | sed -n '/BOOT driver/,$p' | grep -a "ASTRO " | tail -2 | cut -c1-260 || true
echo "presence snapshot: ~/drives-backups/presence-$ts.tsv"
""".replace("__N__", str(len(changed) + len(added)))

out = os.path.join(ROOT, "dist", os.environ.get("DRIVES_OUT") or "drives-deploy.tgz")
with tarfile.open(out, "w:gz") as t:
    def add_bytes(name, data, mode=0o644):
        ti = tarfile.TarInfo(name); ti.size = len(data); ti.mode = mode; t.addfile(ti, io.BytesIO(data))
    add_bytes("drives-deploy/base.sha256", "".join("%s  %s\n" % (h, r) for h, r in sorted(base, key=lambda x: x[1])).encode())
    add_bytes("drives-deploy/install.sh", install.encode(), 0o755)
    for rel, src in changed + added:
        t.add(src, arcname="drives-deploy/files/" + rel)
print("changed:", len(changed), "added:", len(added), "->", out, os.path.getsize(out), "bytes")
for rel, _ in sorted(changed):
    if rel.startswith("ncm_world") or rel.startswith("ncm_league/open77"):
        print("  changed", rel)
print("  + installation.lua/systems.lua in", len(OTHERS), "other resources")
for rel, _ in sorted(added):
    print("  added  ", rel)
