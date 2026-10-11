"""Second pass for city_takeover.py (IDEA-1268): with the camera standing in each 150 m cluster (so the geometry and
the game ad are streamed in), redo the wall check for every placed sign, move any that faced the wrong way, and hide
the game ad under it. The first pass stood only at each 30-sign batch's first sign: rays and hides beyond the streamed
area silently did nothing. Resumable (`fixed` in the plan file).

    python city_takeover_fix.py
"""
import json, math, time
from ncwe_client import Ncwe
import city_takeover as ct

CELL = 150


def main():
    pl = json.load(open(ct.PLAN))
    fixed = set(pl.get("fixed", []))
    clusters = {}
    for c in pl["ads"]:
        k = (math.floor(c["c"][0] / CELL), math.floor(c["c"][1] / CELL))
        clusters.setdefault(k, []).append(c)
    t0 = time.time()
    moved = hid = left = 0
    with Ncwe() as n:
        n.call("lock_view", locked=True, reason="Race Week: checking every sign")
        try:
            for i, (k, group) in enumerate(sorted(clusters.items())):
                if "%d,%d" % k in fixed:
                    continue
                cx = sum(c["c"][0] for c in group) / len(group)
                cy = sum(c["c"][1] for c in group) / len(group)
                cz = max(c["c"][2] for c in group)
                n.call("set_camera", position=[cx, cy, cz + 40], pitch=-50, heading=0, wait=True, timeout_ms=20000)
                names = {c["item"]["name"]: c for c in group}
                q = n.call("query_objects", center=[cx, cy, cz], radius=CELL * 1.5 + 60, source="project", text="rw_city_ad",
                           limit=2000, show=False)
                placed = {o["name"]: o for o in q["objects"] if o.get("name") in names}
                ok, _, _ = ct.orient(n, group)
                want = {it["name"]: (h, it) for h, it in ok}
                fixes, dels, hides = [], [], []
                for name, c in names.items():
                    o = placed.get(name)
                    if not o:
                        continue
                    if name not in want:                 # enclosed on both sides now that it is streamed: leave the ad
                        dels.append(o["id"]); left += 1
                        continue
                    h, it = want[name]
                    hides.append(h)
                    dyaw = abs(((o["rotation"]["yaw"] - it["rotation"]["yaw"] + 540) % 360) - 180)
                    dpos = math.dist(o["position"][:2], it["position"][:2])
                    if dyaw > 1 or dpos > 0.05:
                        fixes.append({"id": o["id"], "position": it["position"], "rotation": it["rotation"]})
                for j in range(0, len(fixes), 30):
                    n.call("transform_objects", items=fixes[j:j + 30])
                if dels:
                    n.call("delete_objects", ids=dels)
                if hides:
                    n.call("delete_objects", ids=hides)
                moved += len(fixes); hid += len(hides)
                fixed.add("%d,%d" % k)
                pl["fixed"] = sorted(fixed)
                json.dump(pl, open(ct.PLAN, "w"), indent=0)
                if i % 20 == 0:
                    n.call("project", action="save")
                print(f"{i + 1}/{len(clusters)} moved {moved} hidden {hid} removed {left} | {time.time() - t0:.0f}s", flush=True)
            n.call("project", action="save")
        finally:
            n.call("lock_view", locked=False)


if __name__ == "__main__":
    main()
