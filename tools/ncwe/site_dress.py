"""Race Week Day 1 site dressing (IDEA-1261): curb barriers, ad takeover and lamp banners around one race node.

Runs against the open NCWE Studio project through NCWE.Mcp.exe (ncwe_client.py). Every placement is checked:
  * barriers sit `CURB` m outside the outermost through-lane on each side, sampled along that lane;
  * a barrier is dropped if any part of it comes within (lane width / 2 + ROAD_CLEAR) of ANY road, highway,
    intersection or crosswalk lane (so cross streets and crossings get gaps by themselves), or within PAVE_CLEAR of
    any pavement lane (walkways and stairs stay open);
  * after placing, a barrier whose ground-snapped z is not at road level (it landed on something) is deleted.
Ads: worldAdvertisementNode screens within AD_RADIUS whose face is seen by drivers are hidden and covered by an NCM
screen scaled to the frame. Lamps: every street lamp at road level gets a back-to-back pair of pole banners.

    python site_dress.py <node_id> [--dry] [--radius 70] [--no-ads] [--no-lamps] [--no-barriers]
"""
import argparse, json, math, os, re, sys
from ncwe_client import Ncwe

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BARRIER = r"base\environment\decoration\public_utility\roadblock\pedestrian_barrier\pedestrian_barrier_a.mesh"
BARRIER_LEN, BARRIER_DEPTH = 4.1, 1.0
SCREEN = {"startfinish": r"ncwe\custom\rw_screen_startfinish_f7281d\rw_screen_startfinish_f7281d.mesh",
          "welcome": r"ncwe\custom\rw_screen_welcome_430026\rw_screen_welcome_430026.mesh"}
POLE = [r"ncwe\custom\rw_pole_welcome_6e012e\rw_pole_welcome_6e012e.mesh",
        r"ncwe\custom\rw_pole_pdm_fc67ac\rw_pole_pdm_fc67ac.mesh"]
CURB, ROAD_CLEAR, PAVE_CLEAR = 4.0, 0.8, 1.0
ROADISH = ("Road", "Highway", "Intersection", "Crosswalk")   # matched as words of a lane kind ("Road intersection")


def is_road(kind):
    return any(w.lower() in kind.lower() for w in ROADISH) and "pavement" not in kind.lower() or "crosswalk" in kind.lower()


def is_through(kind):
    return kind in ("Road", "Highway")


def is_drivable(kind):
    k = kind.lower()
    return k in ("road", "highway") or "intersection" in k
DROPS = []


def nodes():
    src = open(os.path.join(ROOT, "ncm", "core", "data", "nodes.lua"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\{\s*x\s*=\s*(-?[\d.]+),\s*y\s*=\s*(-?[\d.]+),\s*z\s*=\s*(-?[\d.]+),.*?name\s*=\s*\"([^\"]+)\".*?id\s*=\s*\"([^\"]+)\"", src):
        out[m.group(5)] = {"x": float(m.group(1)), "y": float(m.group(2)), "z": float(m.group(3)), "name": m.group(4), "id": m.group(5)}
    return out


def seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    t = 0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    return math.hypot(a[0] + dx * t - p[0], a[1] + dy * t - p[1]), t


def poly_dist(p, pts):
    best = (1e9, None, None)
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        d, t = seg_dist(p, a, b)
        if d < best[0]:
            best = (d, i, t)
    return best


def tangent(pts, i):
    a, b = pts[i], pts[i + 1]
    L = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
    return (b[0] - a[0]) / L, (b[1] - a[1]) / L


def arclen_at(pts, i, t):
    s = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts[:i + 1], pts[1:i + 1]))
    return s + t * math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])


def walk(pts, s0, s1, step):
    """Points every `step` m along the polyline between arc lengths s0..s1: (x, y, z, tx, ty)."""
    out, s = [], 0.0
    want = s0
    for a, b in zip(pts, pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L == 0:
            continue
        while want <= s + L and want <= s1:
            f = (want - s) / L
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f,
                        (b[0] - a[0]) / L, (b[1] - a[1]) / L))
            want += step
        s += L
    return out


def survey(n, node, radius):
    c = [node["x"], node["y"], node["z"]]
    n.call("set_camera", look_at=c, pitch=-80, distance=120, wait=True)
    q = n.call("traffic", action="query", center=c, radius=radius, limit=400)
    lanes = []
    for l in q["lanes"]:
        if l.get("deleted"):
            continue
        d = n.call("traffic", action="lane", key=l["key"])["lane"]
        lanes.append({"key": l["key"], "kind": l["kind"], "flags": l["flags"], "width": l["width"], "pts": d["points"],
                      "next": list(l.get("leads_to") or []), "prev": list(l.get("comes_from") or [])})
    return lanes


def chain(lane, by_key, reach):
    """Extend a lane through its links while they carry straight on (junction lanes included), `reach` m each way.
    A link is taken only if both its ends stay within ~25 deg of the starting lane's axis, so turning lanes are not."""
    pts = list(lane["pts"])
    t0 = tangent(pts, len(pts) // 2 - 1 if len(pts) > 2 else 0)

    def length(ps):
        return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(ps, ps[1:]))

    def straight(l):
        if len(l["pts"]) < 2:
            return -1
        a, b = tangent(l["pts"], 0), tangent(l["pts"], len(l["pts"]) - 2)
        return min(a[0] * t0[0] + a[1] * t0[1], b[0] * t0[0] + b[1] * t0[1])
    for direction in ("next", "prev"):
        cur, grown = lane, 0.0
        while grown < reach:
            cand = [by_key[k] for k in cur[direction] if k in by_key and is_drivable(by_key[k]["kind"])]
            cand = [l for l in cand if straight(l) > 0.9]
            if not cand:
                break
            cur = max(cand, key=straight)
            grown += length(cur["pts"])
            pts = pts + cur["pts"][1:] if direction == "next" else cur["pts"][:-1] + pts
    return dict(lane, pts=pts)


def near(p, z, lane, clear, dz=4.0):
    """Is the lane closer than `clear` to p, at a height that matters (tunnels and overpasses ignored)?"""
    d, i, t = poly_dist(p, lane["pts"])
    if d >= clear:
        return False
    a, b = lane["pts"][i], lane["pts"][i + 1]
    return abs(a[2] + (b[2] - a[2]) * t - z) < dz


def parallel(p, lane, ax, ay):
    _, i, _ = poly_dist(p, lane["pts"])
    lx, ly = tangent(lane["pts"], i)
    return abs(lx * ax + ly * ay) > 0.8


def plan_barriers(node, lanes, half_len):
    p = (node["x"], node["y"])
    roads = [l for l in lanes if l["kind"] in ("Road", "Highway")]
    # the main road: the through lane nearest the node
    main = min(roads, key=lambda l: poly_dist(p, l["pts"])[0])
    _, i, t = poly_dist(p, main["pts"])
    tx, ty = tangent(main["pts"], i)
    nx, ny = ty, -tx                                          # right of the main direction
    # lateral offset of every parallel road lane where it passes the node's cross-section
    by_key = {l["key"]: l for l in lanes}
    par = []
    for l in roads:
        if poly_dist(p, l["pts"])[0] > 60:
            continue
        l = chain(l, by_key, 60)
        d, j, u = poly_dist(p, l["pts"])
        if d > 30:
            continue
        lx, ly = tangent(l["pts"], j)
        if abs(lx * tx + ly * ty) < 0.85:
            continue
        a, b = l["pts"][j], l["pts"][j + 1]
        qx, qy = a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u
        if abs((qx - p[0]) * tx + (qy - p[1]) * ty) > 3:      # the node's cross-section must pass through the lane
            continue
        par.append((((qx - p[0]) * nx + (qy - p[1]) * ny), l, j, u, lx * tx + ly * ty > 0))
    par.sort(key=lambda r: r[0])
    if not par:
        return [], 0, (tx, ty)
    sides = [("L", par[0], -1), ("R", par[-1], +1)]
    blockers = [l for l in lanes if is_road(l["kind"])]
    pave = [l for l in lanes if not is_road(l["kind"])]
    items, dropped = [], 0
    for tag, (lat, lane, j, u, same), sgn in sides:
        lane = chain(by_key[lane["key"]], by_key, half_len + 10)
        pts = lane["pts"] if same else list(reversed(lane["pts"]))
        dd, jj, uu = poly_dist(p, pts)
        s_mid = arclen_at(pts, jj, uu)
        for x, y, z, ax, ay in walk(pts, max(0, s_mid - half_len), s_mid + half_len, BARRIER_LEN):
            rx, ry = ay, -ax                                    # right of travel along the t-aligned walk
            off = sgn * (lane["width"] / 2 + CURB - 2.5)        # CURB is measured from a 5 m lane's centre
            off = sgn * CURB if lane["width"] <= 5 else off
            cx, cy = x + rx * off, y + ry * off
            ends = [(cx, cy), (cx + ax * BARRIER_LEN / 2, cy + ay * BARRIER_LEN / 2), (cx - ax * BARRIER_LEN / 2, cy - ay * BARRIER_LEN / 2),
                    (cx + rx * BARRIER_DEPTH / 2, cy + ry * BARRIER_DEPTH / 2), (cx - rx * BARRIER_DEPTH / 2, cy - ry * BARRIER_DEPTH / 2)]
            why = next((b["key"] for e in ends for b in blockers if near(e, z, b, b["width"] / 2 + ROAD_CLEAR)), None)
            why = why or next((w["key"] for e in ends for w in pave
                               if near(e, z, w, PAVE_CLEAR if parallel(e, w, ax, ay) else w["width"] / 2 + ROAD_CLEAR)), None)
            if why:
                dropped += 1
                DROPS.append((tag, round(cx, 1), round(cy, 1), why))
                continue
            items.append({"asset": BARRIER, "position": [round(cx, 3), round(cy, 3), round(z + 1.5, 3)],
                          "rotation": {"yaw": round(math.degrees(math.atan2(-ax, ay)), 2)},
                          "ground": "bottom", "collision": "box", "name": f"{node['id']}_curb_{tag}_{len(items):03d}",
                          "_road_z": z})
    return items, dropped, (tx, ty)


CHUNK = 30   # NCWE place_objects silently stops at 40 items per call


def place(n, items):
    objs = []
    for i in range(0, len(items), CHUNK):
        objs += n.call("place_objects", items=items[i:i + CHUNK])["objects"]
    return objs


def delete(n, ids):
    for i in range(0, len(ids), 100):
        n.call("delete_objects", ids=ids[i:i + 100])


def place_checked(n, items):
    if not items:
        return [], 0
    road_z = [it.pop("_road_z") for it in items]
    objs = place(n, items)
    bad = [o["id"] for o, z in zip(objs, road_z) if abs(o["position"][2] - z) > 0.7]
    if bad:
        delete(n, bad)
    return [o["id"] for o in objs if o["id"] not in bad], len(bad)


def plan_ads(n, node, road_t, radius, site_screen):
    c = [node["x"], node["y"], node["z"]]
    q = n.call("query_objects", center=c, radius=radius, source="game", text="billboard", limit=200, show=False)
    out = []
    for o in q["objects"]:
        if o.get("node") != "worldAdvertisementNode" or "bounds" not in o or o["position"][2] < node["z"] + 3:
            continue
        yaw = math.radians(o["rotation"]["yaw"])
        fx, fy = math.sin(yaw), -math.cos(yaw)                  # a game ad's face looks along its local -Y
        to_road = (node["x"] - o["position"][0], node["y"] - o["position"][1])
        d = math.hypot(*to_road) or 1
        if (fx * to_road[0] + fy * to_road[1]) / d < 0.25:        # must face roughly towards the line
            continue
        bmin, bmax = o["bounds"]["min"], o["bounds"]["max"]
        H = bmax[2] - bmin[2]
        cy_, sy_ = abs(math.cos(yaw)), abs(math.sin(yaw))
        bx, by = bmax[0] - bmin[0], bmax[1] - bmin[1]
        den = cy_ * cy_ - sy_ * sy_
        W = (bx * cy_ - by * sy_) / den if abs(den) > 0.2 else max(bx, by)
        if W <= 0.5 or H <= 0.5 or not (1.2 < W / H < 4.0):
            continue
        out.append({"hide": o["id"], "item": {
            "asset": site_screen if d < 35 else SCREEN["welcome"],
            "position": [round(o["position"][0] + fx * 0.25, 3), round(o["position"][1] + fy * 0.25, 3), round(bmin[2], 3)],
            "rotation": {"yaw": round(o["rotation"]["yaw"] + 180, 2)},
            "scale": [round(W / 8.4, 3), 1, round(H / 3.6, 3)], "ground": "none",
            "name": f"{node['id']}_screen_{len(out)}"}})
    return out


def plan_lamps(n, node, radius, site_pole):
    c = [node["x"], node["y"], node["z"]]
    q = n.call("query_objects", center=c, radius=radius, source="game", text="street_lamp", limit=200, show=False)
    items, k = [], 0
    for o in q["objects"]:
        b = o["position"]
        if "bounds" not in o or abs(b[2] - node["z"]) > 3 or o["bounds"]["size"][2] < 5:
            continue
        mn, mx = o["bounds"]["min"], o["bounds"]["max"]
        ax, ay = (mn[0] + mx[0]) / 2 - b[0], (mn[1] + mx[1]) / 2 - b[1]
        L = math.hypot(ax, ay)
        if L < 0.5:
            continue
        ax, ay = ax / L, ay / L
        yaw = math.degrees(math.atan2(ay, ax))
        pos = [round(b[0] + ax * 0.65, 3), round(b[1] + ay * 0.65, 3), round(b[2] + 2.4, 3)]
        for s, yy in (("a", yaw), ("b", yaw + 180)):
            items.append({"asset": (POLE[0], site_pole)[k % 2], "position": pos, "rotation": {"yaw": round(yy, 2)}, "ground": "none",
                          "name": f"{node['id']}_pole_banner_{k}{s}"})
        k += 1
    return items, k


def site_art(n, node):
    """Site-named start/finish screen and pole banner: generated, imported, emissive. Returns (screen, pole) assets."""
    import race_week_art as art
    out = os.path.join(ROOT, "ncm", "ncwe", "art", "sites")
    os.makedirs(out, exist_ok=True)
    name = node["name"].upper()
    assets = []
    for slug, make, ev in ((f"rw_screen_{node['id']}", lambda p: art.screen(p, "START · FINISH",
                                                                               "NIGHT CITY MOTORSPORTS · RACE WEEK", name), 4),
                           (f"rw_pole_{node['id']}", lambda p: art.pole(p, name, "START FINISH"), 2)):
        slug = re.sub(r"[^a-z0-9_]", "_", slug.lower())
        png = os.path.join(out, slug + ".png")
        w, h = make(png)
        art.plane(os.path.join(out, slug + ".obj"), slug + ".png", w, h)
        m = n.call("import_model", path=os.path.join(out, slug + ".obj"), name=slug, up_axis="Z", pivot="bottom",
                   scale=1, max_texture_size=2048)["mesh"]
        n.call("custom_meshes", action="material", id=m["id"], index=0, emissive_texture=png,
               emissive_color=[1, 1, 1], emissive_ev=ev)
        assets.append(m["asset"])
    return assets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("node")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--radius", type=float, default=70)
    ap.add_argument("--half", type=float, default=56, help="barrier run each way from the node, metres")
    ap.add_argument("--no-ads", action="store_true")
    ap.add_argument("--no-lamps", action="store_true")
    ap.add_argument("--no-barriers", action="store_true")
    ap.add_argument("--clear", action="store_true", help="delete this node's earlier objects (name prefix) first")
    a = ap.parse_args()
    node = nodes()[a.node]
    report = {"node": node["id"], "name": node["name"]}
    with Ncwe() as n:
        n.call("lock_view", locked=True, reason=f"Race Week: dressing {node['name']}")
        try:
            lanes = survey(n, node, a.radius)
            if a.clear and not a.dry:
                q = n.call("query_objects", center=[node["x"], node["y"], node["z"]], radius=200, source="project",
                           text=node["id"], limit=2000, show=False)
                old_ids = [o["id"] for o in q["objects"] if o.get("name", "").startswith(node["id"])
                           and ("_curb_" in o["name"] or "_pole_banner_" in o["name"])]   # screens stay: their ads are hidden
                delete(n, old_ids)
                report["cleared"] = len(old_ids)
            report["lanes"] = len(lanes)
            road_t = (0, 1)
            site_screen, site_pole = (SCREEN["startfinish"], POLE[1]) if a.dry else site_art(n, node)
            if not a.no_barriers:
                items, dropped, road_t = plan_barriers(node, lanes, a.half)
                report["barriers_planned"], report["barriers_dropped_clearance"] = len(items), dropped
                if not a.dry:
                    ids, bad = place_checked(n, items)
                    report["barriers_placed"], report["barriers_removed_not_at_road_level"] = len(ids), bad
            if not a.no_ads:
                ads = plan_ads(n, node, road_t, a.radius, site_screen)
                report["ads"] = len(ads)
                if not a.dry and ads:
                    place(n, [x["item"] for x in ads])
                    delete(n, [x["hide"] for x in ads])
            if not a.no_lamps:
                poles, k = plan_lamps(n, node, a.radius, site_pole)
                report["lamps"] = k
                if not a.dry and poles:
                    place(n, poles)
            if not a.dry:
                n.call("project", action="save")
        finally:
            n.call("lock_view", locked=False)
    if a.dry:
        report["drops"] = DROPS
    print(json.dumps(report))


if __name__ == "__main__":
    main()
