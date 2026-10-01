#!/usr/bin/env python3
"""Every global node Id in the game's world, read from every streaming sector (KB-249, L246).

NCM Pace's race spline nodes need global node Ids that no vanilla node uses. Rather than pick a range from a sample,
this reads them all: every .streamingsector in the base city and the Phantom Liberty archive is extracted and
converted with WolvenKit in batches, every nodeData `Id` is recorded, and the batch is deleted.

Output (in --out): ids.txt (one Id per line, sorted, unique), summary.json (count, min, max, per-archive and
per-category ranges, how many fall in --check-from/--check-count, and the largest free gaps).

Usage:  python tools/scan-node-ids.py --work <scratch dir> --out <dir> [--check-from 0x3F000000000 --check-count 1190]
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WKIT = os.path.join(ROOT, "ncm", "pace", "build", "wolvenkit-cli", "WolvenKit.CLI.exe")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc"
ARCHIVES = [os.path.join(GAME, "content", "basegame_3_nightcity.archive"), os.path.join(GAME, "ep1", "ep1_1_nightcity.archive")]
BATCH = 400
ID_RE = re.compile(r'"Id": "(\d+)"')


def run(args):
    return subprocess.run([WKIT] + args, capture_output=True, text=True, errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--check-from", default="0x3F000000000")
    ap.add_argument("--check-count", type=int, default=1190)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ids, per = set(), {}
    # RESUMABLE: every batch's ids are appended to partial.txt before its files are deleted, and the extracted pool only
    # holds the sectors not yet read -- a rerun after a stop picks up where it left off.
    partial = os.path.join(a.out, "partial.txt")
    if os.path.exists(partial):
        for line in open(partial):
            k, cat, v = line.rstrip(chr(10)).split(chr(9))
            v = int(v)
            ids.add(v)
            lo, hi = per.get(k + ":" + cat, (v, v))
            per[k + ":" + cat] = (min(lo, v), max(hi, v))
    pf = open(partial, "a")
    log = open(os.path.join(a.out, "progress.log"), "a", encoding="utf-8")

    def say(msg):
        line = time.strftime("%H:%M:%S ") + msg
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()

    for arc in ARCHIVES:
        name = os.path.basename(arc)
        raw = os.path.join(a.work, "raw_" + name)
        if os.path.exists(os.path.join(a.work, "done_" + name)):
            say(f"{name}: already read")
            continue
        if not os.path.isdir(raw):
            say(f"{name}: extracting every .streamingsector")
            r = run(["extract", arc, "-o", raw, "-r", r"\.streamingsector$"])
            if r.returncode != 0:
                say(f"{name}: extract FAILED {r.stdout[-400:]} {r.stderr[-400:]}")
                sys.exit(1)
        files = sorted(glob.glob(os.path.join(raw, "**", "*.streamingsector"), recursive=True))
        say(f"{name}: {len(files)} sectors")
        for b in range(0, len(files), BATCH):
            batch = os.path.join(a.work, "batch")
            out = os.path.join(a.work, "json")
            for d in (batch, out):
                shutil.rmtree(d, ignore_errors=True)
                os.makedirs(d)
            for f in files[b:b + BATCH]:
                shutil.move(f, os.path.join(batch, os.path.basename(f)))
            run(["convert", "s", batch, "-o", out, "-v", "Minimal"])
            got = 0
            for j in glob.glob(os.path.join(out, "*.json")):
                text = open(j, encoding="utf-8", errors="replace").read()
                m = re.search(r'"category": "(\w+)"', text)
                cat = m.group(1) if m else "?"
                key = f"{name}:{cat}"
                found = [int(x) for x in ID_RE.findall(text)]
                found = [x for x in found if x != 0]
                ids.update(found)
                for x in found:
                    pf.write(name + chr(9) + cat + chr(9) + str(x) + chr(10))
                if found:
                    lo, hi = per.get(key, (found[0], found[0]))
                    per[key] = (min(lo, min(found)), max(hi, max(found)))
                got += 1
            pf.flush()
            shutil.rmtree(batch, ignore_errors=True)
            shutil.rmtree(out, ignore_errors=True)
            say(f"{name}: {min(b + BATCH, len(files))}/{len(files)} sectors, {got} converted, {len(ids)} distinct ids so far")
        shutil.rmtree(raw, ignore_errors=True)
        open(os.path.join(a.work, "done_" + name), "w").close()

    s = sorted(ids)
    with open(os.path.join(a.out, "ids.txt"), "w") as f:
        f.write("\n".join(str(x) for x in s))
    start = int(a.check_from, 0)
    end = start + (a.check_count + 1) * 16
    inside = [x for x in s if start <= x <= end]
    gaps = sorted(((s[i + 1] - s[i], s[i], s[i + 1]) for i in range(len(s) - 1)), reverse=True)[:10]
    summary = {"count": len(s), "min": hex(s[0]) if s else None, "max": hex(s[-1]) if s else None,
               "per": {k: [hex(v[0]), hex(v[1])] for k, v in sorted(per.items())},
               "check": {"from": hex(start), "to": hex(end), "vanilla_ids_inside": len(inside), "examples": [hex(x) for x in inside[:10]]},
               "largest_gaps": [{"size": g[0], "after": hex(g[1]), "before": hex(g[2])} for g in gaps]}
    json.dump(summary, open(os.path.join(a.out, "summary.json"), "w"), indent=1)
    say("DONE " + json.dumps({k: summary[k] for k in ("count", "min", "max", "check")}))


if __name__ == "__main__":
    main()
