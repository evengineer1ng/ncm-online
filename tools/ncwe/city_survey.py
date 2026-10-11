"""Survey every game advertisement and street lamp in Night City through NCWE Studio (IDEA-1268, the city takeover).

    python city_survey.py [--step 500] [--out ncm/ncwe/city_survey.json]

Only what is around the editor camera is loaded, and a query returns at most 2,000 objects (nearest first), so the
camera walks a grid and each stop is queried in box tiles per search term; a tile that hits the cap is split in four.
Resumable: stops already in the output file are skipped. Writes after every stop.
"""
import argparse, json, os, sys, time
from ncwe_client import Ncwe

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BOUNDS = (-6500, -8500, 6500, 5000)          # x0, y0, x1, y1 -- the map a returning car may land on (deep.lua MAP)
TERMS = ("billboard", "advertising", "commercial", "screen")
LAMP = "street_lamp"
CAP = 2000


def keep_ad(o):
    return o.get("node") == "worldAdvertisementNode" and "bounds" in o


def keep_lamp(o):
    return "bounds" in o and o["bounds"]["size"][2] >= 5


def slim(o):
    return {k: o[k] for k in ("id", "name", "asset", "position", "rotation", "scale", "bounds") if k in o}


def tile(n, x0, y0, x1, y1, text, keep, out, depth=0):
    q = n.call("query_objects", min=[x0, y0, -200], max=[x1, y1, 700], source="game", text=text, limit=CAP, show=False)
    objs = q["objects"]
    if len(objs) >= CAP and depth < 3:
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        for a, b, c, d in ((x0, y0, mx, my), (mx, y0, x1, my), (x0, my, mx, y1), (mx, my, x1, y1)):
            tile(n, a, b, c, d, text, keep, out, depth + 1)
        return
    for o in objs:
        if keep(o):
            out[o["id"]] = slim(o)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", type=float, default=500)
    ap.add_argument("--out", default=os.path.join(ROOT, "ncm", "ncwe", "city_survey.json"))
    a = ap.parse_args()
    data = {"ads": {}, "lamps": {}, "done": []}
    if os.path.exists(a.out):
        data = json.load(open(a.out))
    done = set(tuple(s) for s in data["done"])
    x0, y0, x1, y1 = BOUNDS
    stops = []
    y = y0 + a.step / 2
    while y < y1:
        x = x0 + a.step / 2
        while x < x1:
            stops.append((round(x), round(y)))
            x += a.step
        y += a.step
    t0 = time.time()
    with Ncwe() as n:
        n.call("lock_view", locked=True, reason="Race Week: surveying the city's billboards")
        try:
            for i, (x, y) in enumerate(stops):
                if (x, y) in done:
                    continue
                n.call("set_camera", position=[x, y, 120], pitch=-60, heading=0, wait=True, timeout_ms=20000)
                h = a.step / 2
                before = (len(data["ads"]), len(data["lamps"]))
                for t in TERMS:
                    tile(n, x - h, y - h, x + h, y + h, t, keep_ad, data["ads"])
                tile(n, x - h, y - h, x + h, y + h, LAMP, keep_lamp, data["lamps"])
                data["done"].append([x, y])
                json.dump(data, open(a.out, "w"))
                print(f"{i + 1}/{len(stops)} ({x},{y}) +{len(data['ads']) - before[0]} ads +{len(data['lamps']) - before[1]} lamps"
                      f" | total {len(data['ads'])} ads {len(data['lamps'])} lamps | {time.time() - t0:.0f}s", flush=True)
        finally:
            n.call("lock_view", locked=False)


if __name__ == "__main__":
    main()
