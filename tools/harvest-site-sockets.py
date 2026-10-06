"""Harvest the game's own AISpots around every NCM race node as candidate population sockets (IDEA-875).

Read-only against the game install. For each node in ncm/core/data/nodes.lua it finds the level-0 exterior
streaming sectors (64 m cells) within --radius, unbundles and serializes them with the WolvenKit CLI, and records
every worldAISpotNode inside the radius: position, yaw, and the vanilla .workspot it plays. The workspot path is
what makes a spot classifiable (sit_chair, rail_lean, cheer, vending_machine ...).

Usage:  python tools/harvest-site-sockets.py --work <scratch dir> [--radius 90] [--out <json>]
"""
import argparse, glob, json, math, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CLI = os.path.join(HERE, "WolvenKit.Console-8.20.0", "WolvenKit.CLI.exe")
ARCHIVE = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content\basegame_3_nightcity.archive"
CELL = 64.0

NODE = re.compile(r'x\s*=\s*(-?[\d.]+),\s*y\s*=\s*(-?[\d.]+),\s*z\s*=\s*(-?[\d.]+).*?name\s*=\s*"([^"]+)".*?id\s*=\s*"([^"]+)"')


def nodes():
    text = open(os.path.join(ROOT, "ncm", "core", "data", "nodes.lua"), encoding="utf-8").read()
    return [dict(x=float(m[0]), y=float(m[1]), z=float(m[2]), name=m[3], id=m[4]) for m in NODE.findall(text)]


def cells(n, radius):
    out = set()
    for cx in range(math.floor((n["x"] - radius) / CELL), math.floor((n["x"] + radius) / CELL) + 1):
        for cy in range(math.floor((n["y"] - radius) / CELL), math.floor((n["y"] + radius) / CELL) + 1):
            out.add((cx, cy))
    return out


def yaw(q):
    # Quaternion (i, j, k, r) to heading about Z, degrees.
    i, j, k, r = (q.get(a, 0.0) for a in ("i", "j", "k", "r"))
    return math.degrees(math.atan2(2 * (r * k + i * j), 1 - 2 * (j * j + k * k)))


def kind(ws):
    w = ws.lower()
    for key, pat in (("cheer", "cheer|crowd_wave"), ("rail_lean", "rail_lean|stand_rail"), ("sit_chair", "sit_chair"),
                     ("sit_ground", "sit_ground|sit_lean|sit_curb"), ("wall_lean", "wall_lean|stand_wall"),
                     ("vending", "vending"), ("phone", "phone|cellphone"), ("smoke", "smoke|cigarette"),
                     ("drink", "drink|coffee|bottle"), ("homeless", "homeless"), ("police", "police|ncpd|patrol"),
                     ("stand", "stand")):
        if re.search(pat, w):
            return key
    return "other"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--radius", type=float, default=90.0)
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "research", "open77", "evidence", "site_sockets.json"))
    a = ap.parse_args()
    ns = nodes()
    want = set()
    for n in ns:
        want |= cells(n, a.radius)
    alt = "|".join(sorted(f"{cx}_{cy}" for cx, cy in want))
    regex = rf"exterior_({alt})_-?\d+_0\.streamingsector$"
    os.makedirs(a.work, exist_ok=True)
    subprocess.run([CLI, "unbundle", ARCHIVE, "-o", a.work, "--regex", regex], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([CLI, "convert", "serialize", a.work], check=True, stdout=subprocess.DEVNULL)
    spots = []
    for f in glob.glob(os.path.join(a.work, "**", "*.streamingsector.json"), recursive=True):
        root = json.load(open(f, encoding="utf-8"))["Data"]["RootChunk"]
        nodes_ = root["nodes"]
        for d in root["nodeData"]["Data"]:
            n = nodes_[d["NodeIndex"]]["Data"]
            if n.get("$type") != "worldAISpotNode":
                continue
            ws = re.findall(r'"\$value":\s*"([^"]+\.workspot)"', json.dumps(n.get("spot", {})))
            p = d["Position"]
            spots.append(dict(x=round(p["X"], 2), y=round(p["Y"], 2), z=round(p["Z"], 2),
                              yaw=round(yaw(d.get("Orientation", {})), 1),
                              workspot=ws[0].replace("\\\\", "\\") if ws else None,
                              sector=os.path.basename(f).replace(".json", "")))
    sites = []
    for n in ns:
        near = []
        for s in spots:
            dist = math.hypot(s["x"] - n["x"], s["y"] - n["y"])
            if dist <= a.radius and abs(s["z"] - n["z"]) <= 25:
                near.append(dict(s, dist=round(dist, 1), kind=kind(s["workspot"] or "")))
        near.sort(key=lambda s: s["dist"])
        kinds = {}
        for s in near:
            kinds[s["kind"]] = kinds.get(s["kind"], 0) + 1
        sites.append(dict(id=n["id"], name=n["name"], x=n["x"], y=n["y"], z=n["z"], count=len(near), kinds=kinds, spots=near))
    json.dump(dict(radius=a.radius, cell=CELL, source="basegame_3_nightcity.archive worldAISpotNode", sites=sites),
              open(a.out, "w", encoding="utf-8"), indent=1)
    for s in sorted(sites, key=lambda s: -s["count"]):
        print(f'{s["count"]:4d}  {s["name"]:<26} {", ".join(f"{k}={v}" for k, v in sorted(s["kinds"].items(), key=lambda kv: -kv[1]))}')
    print(f"{sum(s['count'] for s in sites)} sockets across {len(sites)} nodes -> {a.out}")


if __name__ == "__main__":
    sys.exit(main())
