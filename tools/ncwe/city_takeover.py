"""Race Week city takeover (IDEA-1268): the owner's moodboard on Night City's own billboards and lamp posts.

    python city_takeover.py plan   [--ad-cell 70] [--ad-keep 0.75] [--lamp-cell 90] [--lamp-keep 0.4]
    python city_takeover.py place  [--limit N]      # places the plan into the open NCWE project (resumable)

Input: ncm/ncwe/city_survey.json (city_survey.py) and ncm/ncwe/art/city/panels.json (race_week_moodboard.py + imports).
"Gentle reminders most places you go", not wallpaper: the city is cut into cells and each cell gets at most one
covered ad (the biggest frame there) and a share of the cells nothing at all; lamp banners likewise. Deterministic: the
same survey and settings always give the same plan. Race-node sites already dressed (site_dress.py) are left alone.
Each sign is matched to its frame by shape (wide / square / poster / pole) and stretched to the frame it covers; the
game ad underneath is hidden so nothing flickers through.
"""
import argparse, hashlib, json, math, os, sys, time
from ncwe_client import Ncwe

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SURVEY = os.path.join(ROOT, "ncm", "ncwe", "city_survey.json")
PANELS = os.path.join(ROOT, "ncm", "ncwe", "art", "city", "panels.json")
PLAN = os.path.join(ROOT, "ncm", "ncwe", "city_takeover_plan.json")
NODES = os.path.join(ROOT, "ncm", "core", "data", "race_week_sites.lua")
SKIP_ASSET = ("curved", "afterlife", "hologram")
SITE_CLEAR = 90          # metres around a race node: site_dress.py already dressed it
CHUNK = 30               # KB-408: place_objects silently stops at 40


def h01(*parts):
    return int(hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def frame(o):
    """Face width W, height H, depth D and the outward face direction of a game ad (its face looks along local -Y)."""
    yaw = math.radians(o["rotation"]["yaw"])
    fx, fy = math.sin(yaw), -math.cos(yaw)
    bmin, bmax = o["bounds"]["min"], o["bounds"]["max"]
    bx, by, H = bmax[0] - bmin[0], bmax[1] - bmin[1], bmax[2] - bmin[2]
    c, s = abs(math.cos(yaw)), abs(math.sin(yaw))
    den = c * c - s * s
    if abs(den) > 0.2:
        W, D = (bx * c - by * s) / den, (by * c - bx * s) / den
    else:                                    # near 45 deg the split is ill-conditioned: thin boards
        W, D = max(bx, by) / math.sqrt(2) * 1.0, 0.3
    centre = ((bmin[0] + bmax[0]) / 2, (bmin[1] + bmax[1]) / 2)
    return W, H, max(0.0, D), (fx, fy), centre, bmin[2]


def site_nodes():
    """Race nodes (x, y) from the scars anchor data: any anchor's site centre is close enough to keep clear."""
    pts = []
    txt = open(NODES, encoding="utf-8").read()
    import re
    for m in re.finditer(r"x\s*=\s*(-?[\d.]+),\s*y\s*=\s*(-?[\d.]+)", txt):
        pts.append((float(m.group(1)), float(m.group(2))))
    return pts


def near_site(x, y, sites):
    return any((x - a) ** 2 + (y - b) ** 2 < SITE_CLEAR ** 2 for a, b in sites)


def pools(panels):
    p = {"wide": [], "square": [], "poster": [], "pole": []}
    for r in panels:
        p[r["kind"]].append(r)
    return p


def pick(pool, aspect, key):
    close = [r for r in pool if 0.65 < r["aspect"] / aspect < 1.5]
    cand = close or sorted(pool, key=lambda r: abs(math.log(r["aspect"] / aspect)))[:3]
    return cand[int(h01(key, "panel") * len(cand)) % len(cand)]


def plan(a):
    sv = json.load(open(SURVEY))
    panels = [r for r in json.load(open(PANELS)) if "asset" in r]
    P = pools(panels)
    sites = site_nodes()
    # ---- ads: one per cell (the biggest frame), a share of cells kept
    best = {}
    skipped = {"shape": 0, "site": 0, "tilted": 0, "asset": 0}
    for o in sv["ads"].values():
        if any(k in o["asset"].lower() for k in SKIP_ASSET):
            skipped["asset"] += 1; continue
        if abs(o["rotation"].get("pitch", 0)) > 1 or abs(o["rotation"].get("roll", 0)) > 1:
            skipped["tilted"] += 1; continue
        W, H, D, f, c, z0 = frame(o)
        if W < 1.0 or H < 0.8 or W > 60 or H > 40 or not (0.25 <= W / H <= 8):
            skipped["shape"] += 1; continue
        if near_site(c[0], c[1], sites):
            skipped["site"] += 1; continue
        cell = (math.floor(c[0] / a.ad_cell), math.floor(c[1] / a.ad_cell))
        area = W * H
        if cell not in best or area > best[cell][0]:
            best[cell] = (area, o, (W, H, D, f, c, z0))
    items = []
    for cell, (_, o, (W, H, D, f, c, z0)) in sorted(best.items()):
        if h01("adcell", *cell) > a.ad_keep:
            continue
        asp = W / H
        kind = "wide" if asp >= 1.6 else "square" if asp >= 0.8 else "poster"
        r = pick(P[kind], asp, o["id"])
        off = D / 2 + 0.06
        items.append({"hide": o["id"], "item": {
            "asset": r["asset"], "name": f"rw_city_ad_{r['name']}_{len(items):05d}",
            "position": [round(c[0] + f[0] * off, 3), round(c[1] + f[1] * off, 3), round(z0, 3)],
            "rotation": {"yaw": round(o["rotation"]["yaw"] + 180, 2)},
            "scale": [round(W / r["w"], 4), 1, round(H / r["h"], 4)], "ground": "none"},
            # for the wall check at placement (frames do not all face their local -Y)
            "c": [round(c[0], 3), round(c[1], 3), round(z0 + H / 2, 3)], "f": [round(f[0], 4), round(f[1], 4)],
            "off": round(off, 3), "yaw": o["rotation"]["yaw"]})
    # ---- lamp banners: one lamp per cell, a share kept, back-to-back pair
    lamps = {}
    for o in sv["lamps"].values():
        b = o["position"]
        if near_site(b[0], b[1], sites):
            continue
        cell = (math.floor(b[0] / a.lamp_cell), math.floor(b[1] / a.lamp_cell))
        if cell not in lamps:
            lamps[cell] = o
    poles = []
    for cell, o in sorted(lamps.items()):
        if h01("lampcell", *cell) > a.lamp_keep:
            continue
        b, mn, mx = o["position"], o["bounds"]["min"], o["bounds"]["max"]
        ax, ay = (mn[0] + mx[0]) / 2 - b[0], (mn[1] + mx[1]) / 2 - b[1]
        L = math.hypot(ax, ay)
        if L < 0.5:
            continue
        ax, ay = ax / L, ay / L
        yaw = math.degrees(math.atan2(ay, ax))
        r = P["pole"][int(h01(o["id"], "pole") * len(P["pole"])) % len(P["pole"])]
        pos = [round(b[0] + ax * 0.65, 3), round(b[1] + ay * 0.65, 3), round(b[2] + 2.4, 3)]
        for s, yy in (("a", yaw), ("b", yaw + 180)):
            poles.append({"asset": r["asset"], "position": pos, "rotation": {"yaw": round(yy, 2)}, "ground": "none",
                          "name": f"rw_city_pole_{r['name']}_{len(poles):05d}{s}"})
    blk = lambda p: (math.floor(p[0] / 1000), math.floor(p[1] / 1000), p[0], p[1])
    items.sort(key=lambda x: blk(x["item"]["position"]))
    poles.sort(key=lambda x: blk(x["position"]) + (x["name"],))
    out = {"ads": items, "poles": poles, "skipped": skipped, "settings": vars(a), "placed": {"ads": 0, "poles": 0}}
    json.dump(out, open(PLAN, "w"), indent=0)
    print(json.dumps({"survey_ads": len(sv["ads"]), "survey_lamps": len(sv["lamps"]), "ad_cells": len(best),
                      "ads_covered": len(items), "lamp_cells": len(lamps), "pole_banners": len(poles), "skipped": skipped}))


WALL_M = 3.0   # a side with geometry this close behind the frame is its back


def orient(n, chunk):
    """Raycast out of both faces of each frame; if the planned face is against a wall and the other is open, flip."""
    rays = []
    for c in chunk:
        cx, cy, cz = c["c"]
        fx, fy = c["f"]
        for sgn in (1, -1):
            o = [cx + sgn * fx * (c["off"] + 0.3), cy + sgn * fy * (c["off"] + 0.3), cz]
            rays.append({"origin": o, "direction": [sgn * fx, sgn * fy, 0], "max_distance": WALL_M})
    hits = n.call("raycast", rays=rays, show=False, normal=False)
    res = hits.get("results") or hits.get("hits") or hits.get("rays") or []
    flipped = skipped = 0
    out = []
    for i, c in enumerate(chunk):
        a, b = (res[2 * i] if 2 * i < len(res) else {}), (res[2 * i + 1] if 2 * i + 1 < len(res) else {})
        front = bool(a and (a.get("hit") or a.get("distance") is not None and a.get("position")))
        back = bool(b and (b.get("hit") or b.get("distance") is not None and b.get("position")))
        it = dict(c["item"])
        if front and back:
            skipped += 1        # recessed or enclosed: leave the game's ad
            continue
        if front and not back:
            cx, cy, _ = c["c"]
            fx, fy = c["f"]
            it["position"] = [round(cx - fx * c["off"], 3), round(cy - fy * c["off"], 3), it["position"][2]]
            it["rotation"] = {"yaw": round(c["yaw"], 2)}
            flipped += 1
        out.append((c["hide"], it))
    return out, flipped, skipped


def place(a):
    pl = json.load(open(PLAN))
    t0 = time.time()
    with Ncwe() as n:
        n.call("lock_view", locked=True, reason="Race Week: the city takeover")
        try:
            for kind in ("ads", "poles"):
                todo = pl[kind][pl["placed"][kind]:]
                if a.limit:
                    todo = todo[:a.limit]
                done = pl["placed"][kind]
                for i in range(0, len(todo), CHUNK):
                    chunk = todo[i:i + CHUNK]
                    p = (chunk[0]["item"] if kind == "ads" else chunk[0])["position"]
                    n.call("set_camera", position=[p[0], p[1], p[2] + 60], pitch=-45, heading=0, wait=True, timeout_ms=20000)
                    if kind == "ads":
                        ok, fl, sk = orient(n, chunk)
                        pl.setdefault("stats", {"flipped": 0, "left": 0})
                        pl["stats"]["flipped"] += fl; pl["stats"]["left"] += sk
                        if ok:
                            n.call("place_objects", items=[it for _, it in ok])
                            n.call("delete_objects", ids=[h for h, _ in ok])
                    else:
                        n.call("place_objects", items=chunk)
                    done += len(chunk)
                    pl["placed"][kind] = done
                    json.dump(pl, open(PLAN, "w"), indent=0)
                    if (i // CHUNK) % 10 == 0:
                        n.call("project", action="save")
                    print(f"{kind} {done}/{len(pl[kind])} | {time.time() - t0:.0f}s", flush=True)
            n.call("project", action="save")
        finally:
            n.call("lock_view", locked=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("plan", "place"))
    ap.add_argument("--ad-cell", type=float, default=70)
    ap.add_argument("--ad-keep", type=float, default=0.75)
    ap.add_argument("--lamp-cell", type=float, default=90)
    ap.add_argument("--lamp-keep", type=float, default=0.4)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    if a.cmd == "plan":
        plan(a)
    else:
        place(a)


if __name__ == "__main__":
    main()
