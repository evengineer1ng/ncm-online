#!/usr/bin/env python3
"""Build one closed race-spline source line per authored Paddock oval.

Run with --nodes first, route the emitted points with ncm_pace_bake_legs,
then run with --road-legs. City rings use the directed road graph; an oval
outside that graph uses the authored polar ring from data.ovals.
"""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def authored(path):
    source = path.read_text(encoding="utf-8")
    start = source.index("M.LIST = {")
    end = source.index("local function clamp", start)
    definitions = source[start:end]
    entries = []
    starts = list(re.finditer(r'\{\s*id\s*=\s*"([a-z0-9_]+)"', definitions))
    point_re = re.compile(r'\{\s*x\s*=\s*([\d.-]+),\s*y\s*=\s*([\d.-]+),\s*z\s*=\s*([\d.-]+)\s*\}')
    for i, match in enumerate(starts):
        body = definitions[match.end():starts[i + 1].start() if i + 1 < len(starts) else len(definitions)]
        points = [[float(v) for v in m.groups()] for m in point_re.finditer(body)]
        if len(points) != 4:
            raise ValueError(f"{match.group(1)} has {len(points)} points; expected four")
        inset = re.search(r'lineInsetM\s*=\s*([\d.]+)', body)
        entries.append((match.group(1), points, float(inset.group(1)) if inset else 0.0))
    return entries


def order(points):
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    a0 = math.atan2(points[0][1] - cy, points[0][0] - cx)
    keys = [((math.atan2(p[1] - cy, p[0] - cx) - a0) % (2 * math.pi), i)
            for i, p in enumerate(points[1:], 1)]
    return [0] + [i for _, i in sorted(keys)]


def ring(points, inset):
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    ordered = [points[i] for i in order(points)]
    a0 = math.atan2(ordered[0][1] - cy, ordered[0][0] - cx)
    polar = []
    for i, p in enumerate(ordered):
        t = (math.atan2(p[1] - cy, p[0] - cx) - a0) % (2 * math.pi) if i else 0.0
        polar.append((t, math.hypot(p[0] - cx, p[1] - cy), p[2]))
    polar.append((2 * math.pi, polar[0][1], polar[0][2]))
    radius = sum(p[1] for p in polar[:-1]) / len(points)
    count = max(12, round(2 * math.pi * radius / 10))
    result = []
    for k in range(count):
        t = 2 * math.pi * k / count
        j = next(i for i in range(len(points)) if polar[i][0] <= t < polar[i + 1][0])
        a, b = polar[j], polar[j + 1]
        f = (t - a[0]) / (b[0] - a[0])
        r, z = a[1] + (b[1] - a[1]) * f - inset, a[2] + (b[2] - a[2]) * f
        result.append([cx + r * math.cos(a0 + t), cy + r * math.sin(a0 + t), z])
    return result


def city_ring(name, points, road):
    indices = order(points)
    segments = []
    for k, i in enumerate(indices):
        j = indices[(k + 1) % len(indices)]
        a, b = f"{name}_{i + 1}", f"{name}_{j + 1}"
        leg = road.get((a, b))
        if not leg:
            return None
        # The router deliberately adds off-road checkpoint approach/departure
        # joins. Those are useful for street races, but create hairpins when
        # chained around oval marker checkpoints. Retain the graph-routed road
        # portion only; reconnect its ends with a short smooth spline below.
        end = points[j]
        cut = next((n for n, p in enumerate(leg["points"]) if math.dist(p[:2], end[:2]) < 0.03), None)
        if cut is None or cut < 2:
            raise ValueError(f"{a} -> {b} has no authored endpoint")
        first = min(len(leg["points"]) - 1, math.ceil(leg["onRoadFromM"] / 8))
        last = max(first + 1, cut - math.ceil(leg["offRoadToM"] / 8))
        segment = leg["points"][first:last + 1]
        if len(segment) < 2:
            raise ValueError(f"{a} -> {b} has no road segment after checkpoint joins")
        segments.append(segment)

    # Join adjacent road routes with cubic curves using each route's endpoint
    # direction. Include every next endpoint, and omit only the duplicated
    # final copy of the first endpoint so the loop closes cleanly.
    result = []
    for k, segment in enumerate(segments):
        nxt = segments[(k + 1) % len(segments)]
        p0, p1 = segment[-1], nxt[0]
        if k == 0:
            result.extend(segment)
        else:
            result.extend(segment[1:])
        gap = math.dist(p0[:2], p1[:2])
        if gap > 0.25:
            v0 = [p0[d] - segment[-2][d] for d in range(3)]
            v1 = [nxt[1][d] - p1[d] for d in range(3)]
            n0 = math.hypot(v0[0], v0[1]) or 1.0
            n1 = math.hypot(v1[0], v1[1]) or 1.0
            h = min(7.0, max(1.0, gap * 0.45))
            c0 = [p0[d] + v0[d] / n0 * h for d in range(3)]
            c1 = [p1[d] - v1[d] / n1 * h for d in range(3)]
            steps = max(2, math.ceil(gap / 3.0))
            for q in range(1, steps + 1):
                t = q / steps
                u = 1 - t
                result.append([u**3*p0[d] + 3*u*u*t*c0[d] + 3*u*t*t*c1[d] + t**3*p1[d] for d in range(3)])
    if math.dist(result[-1][:2], result[0][:2]) > 0.03:
        raise ValueError(f"{name} does not close after road joins")
    return result[:-1]


def length(points):
    return sum(math.dist(points[i], points[(i + 1) % len(points)]) for i in range(len(points)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ovals", type=Path, default=ROOT / "ncm/core/data/ovals.lua")
    parser.add_argument("--nodes", type=Path, help="write authored nodes for ncm_pace_bake_legs")
    parser.add_argument("--road-legs", type=Path, help="bake closed spline JSONL from road leg JSONL")
    parser.add_argument("--out", type=Path, help="output JSONL (default stdout)")
    parser.add_argument("--server-lines", type=Path, help="write matching server oval lines as Lua")
    args = parser.parse_args()
    entries = authored(args.ovals)
    if args.nodes:
        with args.nodes.open("w", encoding="utf-8") as f:
            for name, points, _ in entries:
                for i, (x, y, z) in enumerate(points, 1):
                    f.write(f'{{ x = {x}, y = {y}, z = {z}, raceLegal = true, id = "{name}_{i}" }}\n')
        return
    if not args.road_legs:
        parser.error("supply --nodes or --road-legs")
    road = {}
    for line in args.road_legs.read_text(encoding="utf-8").splitlines():
        if line.strip():
            leg = json.loads(line)
            road[(leg["from"], leg["to"])] = leg
    output = []
    for name, points, inset in entries:
        route = city_ring(name, points, road)
        source = "road" if route else "authored"
        if route is None:
            if name != "ncx_octagon":
                raise ValueError(f"{name} has no directed road loop; refuse an unreviewed authored fallback")
            route = ring(points, inset)
        if len(route) < 8:
            raise ValueError(f"{name} has too few spline points")
        output.append({"from": "oval_" + name, "to": "loop", "looped": True,
                       "source": source, "lengthM": round(length(route), 2),
                       "points": [[round(v, 3) for v in p] for p in route]})
        print(f"{name}: {source}, {len(route)} points, {length(route):.0f} m", file=__import__("sys").stderr)
    data = "".join(json.dumps(o, separators=(",", ":")) + "\n" for o in output)
    if args.out:
        args.out.write_text(data, encoding="utf-8")
    else:
        print(data, end="")
    if args.server_lines:
        with args.server_lines.open("w", encoding="utf-8", newline="\n") as f:
            f.write("-- GENERATED by tools/bake-oval-splines.py: the lines in Pace's closed oval splines.\n")
            f.write("PaddockOvalLines = {\n")
            for oval in output:
                encoded = ";".join(",".join(f"{v:.3f}" for v in p) for p in oval["points"])
                f.write(f'  ["{oval["from"]}"] = "{encoded}",\n')
            f.write("}\n")


if __name__ == "__main__":
    main()
