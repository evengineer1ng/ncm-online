#!/usr/bin/env python3
"""Lane-based start grids for every race leg (owner, 2026-10-01: "we need dynamic grid solving to leverage our
understanding of local geometry so everyone gets a fair unblocked start"; L250 step 1).

The old grid was two columns walked back along ONE lane behind the start and carried straight on past its end
(`paddock.live` roadSlots). At Hill Abode that lane was a 27 m driveway, and eight of twelve cars stood behind a
mansion gate. This bake builds each start from the game's own traffic lanes:

  * ANCHOR  of the lanes within 25 m of the start that run the race's way, the one with the longest straight
            walk-back -- the through road beats a driveway or a dead end;
  * COLUMNS the anchor plus its parallel same-direction lanes (the traffic data's `neighborGroupIndex`), each walked
            back on its own; a single wide lane (>= 6 m) carries two tight columns;
  * SLOTS   rows across the columns (pole on the left), staggered by half a row on two columns, 10 m apart from 10 m
            behind the line, compressed to 8 m when the road behind is short -- and NEVER past the end of a lane;
            still short: the opposite-direction lanes of the same road (the start's traffic null area clears them),
            facing the race's way; still short: fewer slots, flagged.

Inputs: the archive exports Pace bakes from (ncm/pace/build/road-data: lane polygons + traffic_persistent) and the
leg bake (ncm/pace/build/legs/legs.jsonl, for the race's direction off each start). Output: the Paddock server's
`server/grid_slots_data.lua` (`PaddockGridSlots["<start>__<next>"]`) and `tools/grid-report.md`.

Usage: python tools/bake-grids.py
"""
import json
import math
import os
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "ncm", "pace", "build", "road-data")
LEGS = os.path.join(ROOT, "ncm", "pace", "build", "legs", "legs.jsonl")
OUT = os.path.join(ROOT, "ncm", "online", "resources", "ncm_paddock", "server", "grid_slots_data.lua")
REPORT = os.path.join(ROOT, "tools", "grid-report.md")

MAX_SLOTS = 20
WALK_M = 150.0
SETBACK_M = 10.0
ROW_M, MIN_ROW_M = 10.0, 8.0
NEAR_M = 30.0
MAX_COLS = 4
CELL = 25.0


def norm(x, y):
    l = math.hypot(x, y)
    return (x / l, y / l) if l > 1e-6 else (0.0, 0.0)


print("loading lanes ...", flush=True)
poly = json.load(open(os.path.join(DATA, "all.lane_polygons.json"), encoding="utf-8"))["Data"]["RootChunk"]["data"]
traffic = json.load(open(os.path.join(DATA, "all.traffic_persistent.json"), encoding="utf-8"))["Data"]["RootChunk"]["data"]["lanes"]
LINES = {}
for e in poly:
    pts = [(p["X"], p["Y"], p["Z"]) for p in e["value"]["outline"]]
    if len(pts) >= 2:
        LINES[e["index"]] = pts
assert len(traffic) == max(LINES) + 1 or len(traffic) >= len(LINES), "traffic and polygon lane counts disagree"


def ins(i):
    out = []
    for x in traffic[i].get("inLanes") or []:
        out.append(x["laneIndex"] if isinstance(x, dict) else int(x))
    return out


WIDTH = {i: float(traffic[i].get("width") or 0) for i in LINES}
GROUP = {i: traffic[i].get("neighborGroupIndex") for i in LINES}
# a spatial hash of every lane segment start
HASH = defaultdict(list)
for i, pts in LINES.items():
    for j, p in enumerate(pts[:-1]):
        HASH[(int(p[0] // CELL), int(p[1] // CELL))].append((i, j))


def near(x, y, z, radius):
    cx, cy = int(x // CELL), int(y // CELL)
    r = int(radius // CELL) + 1
    seen = {}
    for gx in range(cx - r, cx + r + 1):
        for gy in range(cy - r, cy + r + 1):
            for i, j in HASH.get((gx, gy), ()):
                p = LINES[i][j]
                if abs(p[2] - z) > 10:
                    continue
                d = math.hypot(p[0] - x, p[1] - y)
                if d <= radius and (i not in seen or d < seen[i][1]):
                    seen[i] = (j, d)
    return seen


def segdir(pts, j):
    a, b = pts[j], pts[min(j + 1, len(pts) - 1)]
    return norm(b[0] - a[0], b[1] - a[1])


def walk_back(i, j, start):
    """From `start` (a point on lane i near index j) back along the lane and its straightest predecessors."""
    out = [start]
    total, lane, k = 0.0, i, j
    first_dir = None
    for _ in range(60):
        pts = LINES[lane]
        while k >= 0 and total < WALK_M:
            p = pts[k]
            d = math.hypot(p[0] - out[-1][0], p[1] - out[-1][1])
            if d >= 0.5:
                total += d
                out.append(p)
            k -= 1
        if total >= WALK_M:
            break
        # the predecessor running straightest into this lane
        s = segdir(pts, 0)
        best, bestdot = None, 0.8
        for q in ins(lane):
            qp = LINES.get(q)
            if not qp or math.hypot(qp[-1][0] - pts[0][0], qp[-1][1] - pts[0][1]) > 12:
                continue
            qd = segdir(qp, len(qp) - 2)
            dot = qd[0] * s[0] + qd[1] * s[1]
            if dot > bestdot:
                best, bestdot = q, dot
        if best is None:
            break
        lane, k = best, len(LINES[best]) - 1
    return out, total


def along(line, dist):
    """Point and backward direction at `dist` along a walked-back line; None past its end."""
    acc = 0.0
    for a, b in zip(line, line[1:]):
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        if seg > 0 and acc + seg >= dist:
            u = (dist - acc) / seg
            return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u), norm(b[0] - a[0], b[1] - a[1])
        acc += seg
    return None


def race_dir(points, from_m=15.0, to_m=55.0):
    """The race's direction off the start, from the routed road (not the straight join out to it)."""
    acc, a_pt, b_pt = 0.0, None, None
    for a, b in zip(points, points[1:]):
        acc += math.hypot(b[0] - a[0], b[1] - a[1])
        if a_pt is None and acc >= from_m:
            a_pt = b
        if acc >= to_m:
            b_pt = b
            break
    a_pt = a_pt or points[0]
    b_pt = b_pt or points[-1]
    return norm(b_pt[0] - a_pt[0], b_pt[1] - a_pt[1])


def road_entry(points):
    """Where the route first runs on a lane (a node in a plaza or above a highway sits off every lane)."""
    for p in points[:40]:
        if near(p[0], p[1], p[2], 4.0):
            return p
    return points[0]


# ---------------------------------------------------------------------------------- the geometric tracker (v2)
# Lane topology breaks inside junctions: a start node usually sits in one, among short connector lanes whose chain of
# predecessors turns (Hill Abode: every candidate walked back 0-10 m). So the road behind a start is found by
# GEOMETRY: lane centrelines densified to <= 3 m, and a tracker that steps back along the race's direction following
# whatever centreline runs that way.
DENSE = defaultdict(list)       # cell -> [(x, y, z, dx, dy, lane)]
DCELL = 8.0
for i, pts in LINES.items():
    for a, b in zip(pts, pts[1:]):
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        if seg < 0.05:
            continue
        dx, dy = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
        n = max(1, int(seg // 3))
        for k in range(n):
            u = k / n
            x, y, z = a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u
            DENSE[(int(x // DCELL), int(y // DCELL))].append((x, y, z, dx, dy, i))


def dense_near(x, y, z, radius, dz=5.0):
    out = []
    r = int(radius // DCELL) + 1
    cx, cy = int(x // DCELL), int(y // DCELL)
    for gx in range(cx - r, cx + r + 1):
        for gy in range(cy - r, cy + r + 1):
            for q in DENSE.get((gx, gy), ()):
                if abs(q[2] - z) <= dz and math.hypot(q[0] - x, q[1] - y) <= radius:
                    out.append(q)
    return out


STEP = 4.0


def track(node, fdir):
    """The road behind a start: [(x, y, z, fx, fy)] stepping back STEP m at a time, race direction at each point."""
    # a lane running the race's way, or (a one-way street raced against its flow) the other way -- cars always face
    # the race; a same-direction lane wins over an opposite one 5 m nearer
    start = None
    for threshold in (0.85, 0.6):
        for radius in (6.0, 12.0, 20.0, 30.0):
            cands = [q for q in dense_near(node[0], node[1], node[2], radius, 10.0) if abs(q[3] * fdir[0] + q[4] * fdir[1]) >= threshold]
            if cands:
                start = min(cands, key=lambda q: math.hypot(q[0] - node[0], q[1] - node[1]) + (0 if q[3] * fdir[0] + q[4] * fdir[1] > 0 else 5))
                break
        if start:
            break
    if not start:
        return []
    sgn = 1 if start[3] * fdir[0] + start[4] * fdir[1] > 0 else -1
    fx, fy = start[3] * sgn, start[4] * sgn
    path = [(start[0], start[1], start[2], fx, fy)]
    x, y, z = start[0], start[1], start[2]
    misses, depth = 0, 0.0
    while depth < WALK_M:
        px, py = x - fx * STEP, y - fy * STEP
        cands = [q for q in dense_near(px, py, z, 3.5, 4.0) if abs(q[3] * fx + q[4] * fy) >= 0.8]
        if cands:
            q = min(cands, key=lambda q: math.hypot(q[0] - px, q[1] - py))
            x, y, z = q[0], q[1], q[2]
            qs = 1 if q[3] * fx + q[4] * fy > 0 else -1
            nfx, nfy = norm(fx * 0.6 + q[3] * qs * 0.4, fy * 0.6 + q[4] * qs * 0.4)
            fx, fy = nfx, nfy
            misses = 0
        else:
            misses += 1
            if misses > 2:
                break
            x, y = px, py              # a junction gap: carry on a few metres
        depth += STEP
        if misses == 0:
            path.append((x, y, z, fx, fy))
    return path


def columns_along(path, max_cols=4, opposite=False):
    """Parallel same-direction lane centrelines beside the tracked road, as lateral offsets that persist."""
    samples = []
    for (x, y, z, fx, fy) in path:
        rx, ry = -fy, fx
        offs = []
        for q in dense_near(x, y, z, 12.0, 4.0):
            dot = q[3] * fx + q[4] * fy
            if dot < 0.85 and not (opposite and dot <= -0.85):
                continue
            lon = (q[0] - x) * fx + (q[1] - y) * fy
            if abs(lon) > 2.0:
                continue
            lat = (q[0] - x) * rx + (q[1] - y) * ry
            if abs(lat) <= 11.0:
                offs.append((lat, q))
        samples.append(offs)
    # bands from the first samples (near the line), 2.5 m apart
    seeds = sorted({round(lat / 0.5) * 0.5 for s in samples[:4] for lat, _ in s})
    bands = []
    for b in seeds:
        if all(abs(b - c) > 2.5 for c in bands):
            bands.append(b)
    bands = sorted(bands, key=abs)[:max_cols]
    cols = []
    for b in bands:
        pts, depth, gaps = [], 0.0, 0
        for k, s in enumerate(samples):
            hit = [q for lat, q in s if abs(lat - b) <= 1.5]
            if hit:
                q = min(hit, key=lambda q: abs(((q[0] - path[k][0]) * -path[k][4] + (q[1] - path[k][1]) * path[k][3]) - b))
                pts.append((q[0], q[1], q[2], path[k][3], path[k][4], k * STEP))
                depth = k * STEP
                gaps = 0
            else:
                gaps += 1
                if gaps > 2:
                    break
        if len(pts) >= 3:
            cols.append({"lat": b, "pts": pts, "depth": depth, "lane": None})
    return cols


def col_at(col, dist):
    """The column's point nearest `dist` m behind the line (within 2.5 m), or None."""
    best = None
    for p in col["pts"]:
        d = abs(p[5] - dist)
        if d <= 2.5 and (best is None or d < best[0]):
            best = (d, p)
    return best and best[1][:5]


def solve(node, fdir):
    path = track(node, fdir)
    if len(path) < 3:
        return None
    best = None
    for opposite in (False, True):
        g = layout(path, columns_along(path, opposite=opposite))
        if g and opposite:
            g["flags"].append("uses_opposite_lanes")
        if g and (best is None or len(g["slots"]) > len(best["slots"])):
            best = g
        if best and len(best["slots"]) >= 12:
            break
    return best


def layout(path, cols):
    if not cols:
        return None
    cols.sort(key=lambda c: c["lat"])       # pole on the left
    formation = "lanes" if len(cols) >= 3 else ("staggered" if len(cols) == 2 else "single")
    tight = False
    if len(cols) == 1:
        p0 = cols[0]["pts"][0]
        lanes_here = [q for q in dense_near(p0[0], p0[1], p0[2], 1.5, 3.0)]
        if lanes_here and max(WIDTH.get(q[5], 0) for q in lanes_here) >= 6:
            tight, formation = True, "tight"

    def place(rowm):
        slots = []
        ncols = 2 if tight else len(cols)
        for r in range(40):
            for ci in range(ncols):
                if len(slots) >= MAX_SLOTS:
                    return slots
                c = cols[0] if tight else cols[ci]
                stagger = (rowm / 2) if (ncols == 2 and ci == 1) else 0
                dist = SETBACK_M + r * rowm + stagger
                if dist > c["depth"]:
                    continue
                p = col_at(c, dist)
                if not p:
                    continue
                x, y, z, fx, fy = p
                if tight:
                    off = -1.6 if ci == 0 else 1.6
                    x, y = x + (-fy) * off, y + fx * off
                # lanes that merge further back bring two columns together: never set two cars within 3 m
                if any(math.hypot(x - o["x"], y - o["y"]) < 3.0 for o in slots):
                    continue
                slots.append({"x": round(x, 1), "y": round(y, 1), "z": round(z, 1),
                              "h": round(math.degrees(math.atan2(fy, fx)), 1), "col": ci + 1, "row": r + 1})
        return slots

    rowm = ROW_M
    slots = place(rowm)
    if len(slots) < 12:
        rowm = MIN_ROW_M
        slots = place(rowm)
    flags = [] if len(slots) >= 12 else ["short"]
    return {"formation": formation, "cols": 2 if tight else len(cols), "depth": round(max(c["depth"] for c in cols)),
            "rowM": rowm, "anchorLane": None, "slots": slots, "flags": flags}



def main():
    legs = [json.loads(l) for l in open(LEGS, encoding="utf-8") if l.strip()]
    print(f"{len(legs)} legs", flush=True)
    out, report = {}, []
    for n, leg in enumerate(sorted(legs, key=lambda l: (l["from"], l["to"]))):
        pts = [tuple(p) for p in leg["points"]]
        g = solve(pts[0], race_dir(pts))
        if not g:
            g = solve(road_entry(pts), race_dir(pts))
            if g:
                g["flags"].append("anchored_on_road_entry")
        key = f'{leg["from"]}__{leg["to"]}'
        if g:
            out[key] = g
        report.append((key, g))
        if n % 100 == 0:
            print(f"  {n}/{len(legs)}", flush=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- GENERATED by tools/bake-grids.py from the game's traffic lanes -- do not edit by hand (L250).\n")
        f.write("-- Start grids per race leg: slots on drivable lane centrelines only, pole first. Server only.\n")
        f.write("-- Each slot: x, y, z, h (race heading, degrees), col, row. Hand overrides: ncm/core/data/grid_overrides.lua.\n")
        f.write("PaddockGridSlots = {\n")
        for key in sorted(out):
            g = out[key]
            enc = ";".join(f'{s["x"]},{s["y"]},{s["z"]},{s["h"]},{s["col"]},{s["row"]}' for s in g["slots"])
            f.write(f'  ["{key}"] = {{ formation = "{g["formation"]}", cols = {g["cols"]}, depth = {g["depth"]}, flags = "{",".join(g["flags"])}", slots = "{enc}" }},\n')
        f.write("}\n")
    by_start = defaultdict(list)
    for key, g in report:
        by_start[key.split("__")[0]].append((key, g))
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Start grid report (generated by tools/bake-grids.py)\n\n")
        f.write("| start node | legs | formations | columns | depth (m) | slots (min-max) | flagged |\n|---|---|---|---|---|---|---|\n")
        for start in sorted(by_start):
            gs = [g for _, g in by_start[start] if g]
            none = len(by_start[start]) - len(gs)
            forms = sorted({g["formation"] for g in gs})
            cols = sorted({g["cols"] for g in gs})
            depth = f'{min(g["depth"] for g in gs)}-{max(g["depth"] for g in gs)}' if gs else "-"
            slots = f'{min(len(g["slots"]) for g in gs)}-{max(len(g["slots"]) for g in gs)}' if gs else "-"
            flagged = sum(1 for g in gs if g["flags"]) + none
            f.write(f'| {start} | {len(by_start[start])} | {", ".join(forms) or "NONE"} | {",".join(map(str, cols))} | {depth} | {slots} | {flagged} |\n')
    solved = sum(1 for _, g in report if g)
    short = sum(1 for _, g in report if g and "short" in g["flags"])
    print(f"{solved}/{len(report)} legs solved, {short} short -> {os.path.relpath(OUT, ROOT)}, {os.path.relpath(REPORT, ROOT)}")


if __name__ == "__main__":
    main()
