#!/usr/bin/env python3
"""Read the points the owner marked in game with /ncm.mark (L236) back out of the client's own log.

ncm_paddock/client/marks.lua prints one fixed line per mark into red4ext/logs/open77-*.log:
    NCMMARK {"set":"corpo_plaza","n":1,"x":..,"y":..,"z":..,"src":"waypoint","label":".."}
plus {"undo":true} and {"clear":true} lines. This replays them in order (newest log last) and prints each set as it
stands, and with --oval, as a ready-to-paste `data.ovals` entry.

Usage:  python tools/read-marks.py [--set NAME] [--oval] [--since HOURS]
"""
import argparse
import glob
import json
import os
import re
import time

LOGS = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\red4ext\logs"
LINE = re.compile(r"NCMMARK (\{.*\})")


def replay(since_hours):
    cutoff = time.time() - since_hours * 3600
    files = [f for f in glob.glob(os.path.join(LOGS, "open77-*.log")) if os.path.getmtime(f) >= cutoff]
    # rotated files: open77-<stamp>.N.log are OLDER than open77-<stamp>.log; order by mtime
    files.sort(key=os.path.getmtime)
    sets = {}
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = LINE.search(line)
                if not m:
                    continue
                try:
                    e = json.loads(m.group(1))
                except ValueError:
                    continue
                s = sets.setdefault(e["set"], [])
                if e.get("clear"):
                    s.clear()
                elif e.get("undo"):
                    if s:
                        s.pop()
                else:
                    n = int(e["n"])
                    del s[n - 1:]            # a re-list or a mark after an undo rewrites from its index
                    s.append(e)
    return sets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set")
    ap.add_argument("--oval", action="store_true")
    ap.add_argument("--since", type=float, default=48)
    a = ap.parse_args()
    sets = replay(a.since)
    if not sets:
        print("no NCMMARK lines in the last %g h of %s" % (a.since, LOGS))
        return
    for name, pts in sorted(sets.items()):
        if a.set and name != a.set:
            continue
        print("%s: %d point(s)" % (name, len(pts)))
        for i, p in enumerate(pts, 1):
            print("  #%d  x=%.2f y=%.2f z=%.2f  (%s) %s" % (i, p["x"], p["y"], p["z"], p["src"], p.get("label", "")))
        if a.oval and pts:
            body = ", ".join("{ x = %.2f, y = %.2f, z = %.2f }" % (p["x"], p["y"], p["z"]) for p in pts)
            title = name.replace("_", " ").title()
            print('\n        { id = "%s", name = "%s Oval", region = "?", points = { %s } },\n' % (name, title, body))


if __name__ == "__main__":
    main()
