#!/usr/bin/env python3
"""L327: install Custom Shaders Patch (and place Content Manager) for NCM's Assetto Corsa embodiment -- reversibly.

The owner downloaded both archives (C:/Users/eveng/Downloads). CSP's archive is `dwrite.dll` + `extension/`, copied into
the AC root. Every file written is recorded with a copy of anything it overwrote under
%LOCALAPPDATA%/NCM/ac-mods/<stamp>/, so `--uninstall` puts the folder back exactly. Content Manager is placed in
tools/assetto/ContentManager/ (gitignored); it needs no install.

Usage:  python tools/assetto-install-csp.py [--csp ZIP] [--cm ZIP] [--dry-run]
        python tools/assetto-install-csp.py --uninstall [<stamp>]
"""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import zipfile

AC = r"C:\Program Files (x86)\Steam\steamapps\common\assettocorsa"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STORE = os.path.join(os.environ.get("LOCALAPPDATA", ""), "NCM", "ac-mods")
CM_DIR = os.path.join(ROOT, "tools", "assetto", "ContentManager")


def running(name):
    out = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {name}"], capture_output=True, text=True).stdout
    return name.lower() in out.lower()


def install(a):
    if running("acs.exe") or running("AssettoCorsa.exe"):
        sys.exit("Assetto Corsa is running -- close it first")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    root = os.path.join(STORE, stamp)
    record = {"stamp": stamp, "ac": AC, "files": [], "cm": None}
    z = zipfile.ZipFile(a.csp)
    for info in z.infolist():
        name = info.filename.replace("\\", "/")
        if name.endswith("/"):
            continue
        if name.startswith("/") or ".." in name.split("/"):
            sys.exit("unsafe path " + name)
        dest = os.path.join(AC, *name.split("/"))
        existed = os.path.exists(dest)
        entry = {"path": name, "existed": existed}
        if not a.dry_run:
            if existed:
                keep = os.path.join(root, "overwritten", *name.split("/"))
                os.makedirs(os.path.dirname(keep), exist_ok=True)
                shutil.copy2(dest, keep)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)
        record["files"].append(entry)
    if a.cm:
        cz = zipfile.ZipFile(a.cm)
        if not a.dry_run:
            os.makedirs(CM_DIR, exist_ok=True)
            for info in cz.infolist():
                if info.filename.endswith("/") or ".." in info.filename:
                    continue
                with cz.open(info) as src, open(os.path.join(CM_DIR, os.path.basename(info.filename)), "wb") as out:
                    shutil.copyfileobj(src, out)
        record["cm"] = CM_DIR
    if not a.dry_run:
        os.makedirs(root, exist_ok=True)
        json.dump(record, open(os.path.join(root, "record.json"), "w", encoding="utf-8"), indent=1)
    print(f"{'would install' if a.dry_run else 'installed'} {len(record['files'])} CSP file(s) into {AC}; "
          f"{sum(1 for f in record['files'] if f['existed'])} overwrote existing; record {root}")
    if a.cm:
        print("Content Manager ->", CM_DIR)


def uninstall(stamp):
    stamps = sorted(os.listdir(STORE)) if os.path.isdir(STORE) else []
    stamp = stamps[-1] if stamp in (None, "latest") and stamps else stamp
    root = os.path.join(STORE, stamp)
    record = json.load(open(os.path.join(root, "record.json"), encoding="utf-8"))
    for f in reversed(record["files"]):
        dest = os.path.join(record["ac"], *f["path"].split("/"))
        if f["existed"]:
            shutil.copy2(os.path.join(root, "overwritten", *f["path"].split("/")), dest)
        elif os.path.exists(dest):
            os.remove(dest)
    print("restored", len(record["files"]), "file(s) from", stamp)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csp", default=r"C:\Users\eveng\Downloads\lights-patch-v0.2.11.zip")
    ap.add_argument("--cm", default=r"C:\Users\eveng\Downloads\content-manager.zip")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--uninstall", nargs="?", const="latest")
    a = ap.parse_args()
    if a.uninstall:
        uninstall(a.uninstall)
    else:
        install(a)
