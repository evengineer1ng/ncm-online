#!/usr/bin/env python3
"""Hand-install the dev server's required mods into the game folder (DEV ONLY; owner ruling 2026-09-29, KB-215).

Why: a raw-address join to the development server never asks for the mod manifest (KB-126), so the launcher
projects none of NCM's packages there. The owner does not want dev listed publicly, and the launcher path is
already proven on Online, so for dev testing the packages are copied in by hand.

What it does: reads `requiredMods.packages` from the dev server.jsonc, takes each package's zip from the server's
content-addressed store (`.open77/mods/<sha256>.blob`), and extracts it over the game folder. Every file it writes
is recorded, with a copy of anything it overwrote, under `%LOCALAPPDATA%/NCM/dev-mods/<timestamp>/`, so
`--uninstall` can put the folder back exactly.

Usage:  python tools/dev-hand-install-mods.py [--dry-run] [--only ncm-pace,...]
        python tools/dev-hand-install-mods.py --uninstall [<timestamp>]   (latest when omitted)
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "open77", "server")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
STORE = os.path.join(os.environ.get("LOCALAPPDATA", ""), "NCM", "dev-mods")


def packages():
    text = open(os.path.join(SERVER, "server.jsonc"), encoding="utf-8").read()
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    cfg = json.loads(text)
    return cfg["requiredMods"]["packages"]


def blob_for(pkg):
    h = pkg.get("sha256") or ""
    path = os.path.join(SERVER, ".open77", "mods", h + ".blob")
    if not os.path.exists(path):
        sys.exit("missing blob for %s: %s" % (pkg.get("id"), path))
    got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if got != h:
        sys.exit("blob hash mismatch for %s" % pkg.get("id"))
    return path


def install(args):
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    root = os.path.join(STORE, stamp)
    record = {"stamp": stamp, "game": GAME, "files": []}
    only = set(args.only.split(",")) if args.only else None
    for pkg in packages():
        if only and pkg.get("id") not in only:
            continue
        z = zipfile.ZipFile(blob_for(pkg))
        for info in z.infolist():
            name = info.filename.replace("\\", "/")
            if name.endswith("/"):
                continue
            if name.startswith("/") or ".." in name.split("/"):
                sys.exit("unsafe path in %s: %s" % (pkg.get("id"), name))
            dest = os.path.join(GAME, *name.split("/"))
            existed = os.path.exists(dest)
            print(("overwrite " if existed else "new       ") + pkg["id"] + "  " + name)
            if args.dry_run:
                continue
            entry = {"package": pkg["id"], "path": name, "existed": existed}
            if existed:
                backup = os.path.join(root, "overwritten", *name.split("/"))
                os.makedirs(os.path.dirname(backup), exist_ok=True)
                shutil.copy2(dest, backup)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)
            record["files"].append(entry)
    if args.dry_run:
        return
    os.makedirs(root, exist_ok=True)
    json.dump(record, open(os.path.join(root, "record.json"), "w"), indent=1)
    print("installed %d file(s); record %s" % (len(record["files"]), root))


def uninstall(args):
    stamps = sorted(os.listdir(STORE)) if os.path.isdir(STORE) else []
    stamp = args.uninstall if isinstance(args.uninstall, str) and args.uninstall != "latest" else (stamps[-1] if stamps else None)
    if not stamp:
        sys.exit("nothing to uninstall")
    root = os.path.join(STORE, stamp)
    record = json.load(open(os.path.join(root, "record.json")))
    for e in record["files"]:
        dest = os.path.join(GAME, *e["path"].split("/"))
        if e["existed"]:
            shutil.copy2(os.path.join(root, "overwritten", *e["path"].split("/")), dest)
            print("restored " + e["path"])
        elif os.path.exists(dest):
            os.remove(dest)
            print("removed  " + e["path"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--uninstall", nargs="?", const="latest")
    args = ap.parse_args()
    if args.uninstall:
        uninstall(args)
    else:
        install(args)


if __name__ == "__main__":
    main()
