"""Lay a run of barriers along a traffic lane at a lateral offset (NCWE, IDEA-1261).

Input JSON (stdin or file): {"lane": [[x,y,z],...], "offset": m (+ = right of travel), "from": m, "to": m,
"pitch": m (barrier length), "asset": path, "skip": [[from,to],...] (arc-length gaps: crossings, stairs)}.
Output: NCWE place_objects items, each centred on the offset line, its long axis (+Y) along the lane.
Yaw follows NCWE: 0 faces +Y, counter-clockwise from above, so a tangent (tx, ty) is yaw atan2(-tx, ty).
"""
import json, math, sys


def resample(pts, step):
    out, carry = [], 0.0
    s = 0.0
    for (ax, ay, az), (bx, by, bz) in zip(pts, pts[1:]):
        seg = math.hypot(bx - ax, by - ay)
        if seg == 0:
            continue
        t = carry
        while t <= seg:
            f = t / seg
            out.append((s + t, ax + (bx - ax) * f, ay + (by - ay) * f, az + (bz - az) * f, (bx - ax) / seg, (by - ay) / seg))
            t += step
        carry = t - seg
        s += seg
    return out


def main():
    a = json.load(open(sys.argv[1], encoding="utf-8") if len(sys.argv) > 1 else sys.stdin)
    pitch = a.get("pitch", 4.1)
    items = []
    for s, x, y, z, tx, ty in resample(a["lane"], pitch):
        if s < a.get("from", 0) or s > a.get("to", 1e9):
            continue
        if any(lo <= s <= hi for lo, hi in a.get("skip", [])):
            continue
        rx, ry = ty, -tx  # right of travel
        off = a["offset"]
        items.append({
            "asset": a["asset"],
            "position": [round(x + rx * off, 3), round(y + ry * off, 3), round(z + 1.0, 3)],
            "rotation": {"yaw": round(math.degrees(math.atan2(-tx, ty)), 2)},
            "ground": "bottom",
            "collision": "box",
            "appearance": a.get("appearance", "default"),
            "name": "%s_%03d" % (a.get("name", "barrier"), len(items)),
        })
    json.dump({"s_range": [a.get("from"), a.get("to")], "items": items}, sys.stdout, indent=0)


if __name__ == "__main__":
    main()
