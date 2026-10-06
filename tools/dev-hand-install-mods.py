#!/usr/bin/env python3
"""Hand-install the dev server's required mods into the game folder (DEV ONLY; owner ruling 2026-09-29, KB-215).

Why: a raw-address join to the development server never asks for the mod manifest (KB-126), so the launcher
projects none of NCM's packages there. The owner does not want dev listed publicly, and the launcher path is
already proven on Online, so for dev testing the packages are copied in by hand.

What it does: reads `requiredMods.packages` from the dev server.jsonc, takes each package's zip from the server's
content-addressed store (`.open77/mods/<sha256>.blob`), and extracts it over the game folder. Every file it writes
is recorded, with a copy of anything it overwrote, under `%LOCALAPPDATA%/NCM/dev-mods/<timestamp>/`, so
`--uninstall` can put the folder back exactly.

RED4ext's ignore list (KB-231, 2026-09-30): an Online launch makes the launcher write `red4ext/config.ini` with every
plugin Online does not declare under `[plugins] ignored`, and that list survives into the next dev launch -- so even
correctly installed DLLs never load. After installing, this tool removes exactly the installed packages' own plugin
folders from that list (never anything else: `ncm_radial` stays out by owner ruling, and third-party single-player
mods are left as the launcher set them). The original config.ini is kept with the record, and `--uninstall` restores it.

Usage:  python tools/dev-hand-install-mods.py [--dry-run] [--only ncm-pace,...] [--extra-zip dist/x.zip ...]
        (--extra-zip: a package not yet declared by the dev server -- a spike -- installed and recorded the same way)
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
    sources = [(pkg, blob_for(pkg)) for pkg in packages() if not (only and pkg.get("id") not in only)]
    for extra in args.extra_zip or []:
        if not os.path.exists(extra):
            sys.exit("missing --extra-zip " + extra)
        sources.append(({"id": os.path.splitext(os.path.basename(extra))[0]}, extra))
    for pkg, blob in sources:
        z = zipfile.ZipFile(blob)
        for info in z.infolist():
            name = info.filename.replace("\\", "/")
            if name.endswith("/"):
                continue
            if name.startswith("/") or ".." in name.split("/"):
                sys.exit("unsafe path in %s: %s" % (pkg.get("id"), name))
            dest = os.path.join(GAME, *name.split("/"))
            existed = os.path.exists(dest)
            print(("overwrite " if existed else "new       ") + pkg["id"] + "  " + name)
            entry = {"package": pkg["id"], "path": name, "existed": existed}
            if args.dry_run:
                record["files"].append(entry)
                continue
            if existed:
                backup = os.path.join(root, "overwritten", *name.split("/"))
                os.makedirs(os.path.dirname(backup), exist_ok=True)
                shutil.copy2(dest, backup)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)
            record["files"].append(entry)
    plugin_dirs = sorted({e["path"].split("/")[2] for e in record["files"]
                          if e["path"].startswith("red4ext/plugins/") and e["path"].count("/") >= 3})
    if args.dry_run:
        print("would un-ignore in red4ext/config.ini: " + (", ".join(plugin_dirs) or "(nothing)"))
        return
    os.makedirs(root, exist_ok=True)
    unignore(plugin_dirs, root, record)
    json.dump(record, open(os.path.join(root, "record.json"), "w"), indent=1)
    print("installed %d file(s); record %s" % (len(record["files"]), root))


NEVER_UNIGNORE = {"ncm_radial"}          # owner ruling: Radial stays out (KB-182)


def unignore(plugin_dirs, root, record):
    cfg = os.path.join(GAME, "red4ext", "config.ini")
    if not os.path.exists(cfg):
        return
    text = open(cfg, encoding="utf-8").read()
    m = re.search(r"^(ignored\s*=\s*\[)([^\]]*)(\])", text, flags=re.M)
    if not m:
        print("red4ext/config.ini has no ignored list; nothing to un-ignore")
        return
    names = re.findall(r'"([^"]*)"', m.group(2))
    drop = {d for d in plugin_dirs if d not in NEVER_UNIGNORE}
    keep = [n for n in names if n not in drop]
    removed = [n for n in names if n in drop]
    if not removed:
        print("red4ext/config.ini ignores none of the installed plugins")
        return
    shutil.copy2(cfg, os.path.join(root, "config.ini.before"))
    record["configIni"] = "config.ini.before"
    body = ", ".join('"%s"' % n for n in keep)
    text = text[:m.start(2)] + body + text[m.end(2):]
    open(cfg, "w", encoding="utf-8", newline="").write(text)
    print("un-ignored in red4ext/config.ini: " + ", ".join(removed) + "  (still ignored: " + (", ".join(keep) or "none") + ")")


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
    if record.get("configIni"):
        shutil.copy2(os.path.join(root, record["configIni"]), os.path.join(GAME, "red4ext", "config.ini"))
        print("restored red4ext/config.ini")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--extra-zip", action="append")
    ap.add_argument("--uninstall", nargs="?", const="latest")
    args = ap.parse_args()
    if args.uninstall:
        uninstall(args)
    else:
        install(args)


if __name__ == "__main__":
    main()
