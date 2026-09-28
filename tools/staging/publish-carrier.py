#!/usr/bin/env python3
"""Publish the NCM Carrier to a server: store the blob, declare it, and un-park requiredMods.

    python3 publish-carrier.py <server-root> --zip dist/ncm-carrier-0.1.0.zip --enable
    python3 publish-carrier.py <server-root>                                   # show what is declared
    python3 publish-carrier.py <server-root> --remove                          # withdraw it

**THE STORE IS THE SOURCE OF TRUTH. THIS SCRIPT DECLARES WHAT IS ALREADY IN IT.**

Getting a blob into the store is not this script's job and there is **more than one way to do it**: Warden's
import at `http://127.0.0.1:11780`, or an operator placing files and configuring them the way
`configure-required-mods-https.py` does for Production. Both are legitimate.

What this script will not do any more is *invent* store contents. An earlier version wrote the blob and
metadata by hand and declared them in the same breath; it served for one session and the entry was gone
after the next restart (`KB-124`). **The mechanism was never established** -- it may have been a
reconciliation against a catalogue, or a mismatch in the entry itself -- so the fix is not a theory about
ownership, it is to stop guessing: read the store, declare exactly what is there.

**That also fixes a bug guessing caused.** Warden derives its own id and version from the file name --
`ncm-carrier-0.1.0.zip` became id `ncm-carrier-0-1-0` at version `1.0.0`, not `ncm-carrier` at `0.1.0`. A
declaration naming an id the store does not hold can never resolve. So the id and version come **from the
store metadata**, never from an assumption in this file.

The server root is a PARAMETER (`KB-120`). Development is `tools/open77/server`; the Lightsail default is
kept only so Production is not a special case. **Pass the root explicitly and read what you passed** -- this
script prints it back before it writes anything.

NEVER PRINTS THE LICENCE. It reads server.jsonc and prints only requiredMods fields.

RECOVERY, which is the reason hosting beats a manual copy. If the carrier stops the game launching, the fix
is server-side and takes one command -- `python3 publish-carrier.py <root> --remove`, restart, rejoin -- with
nothing to hunt for in the game directory. The launcher removes what it projected. That is strictly better
than deleting DLLs by hand and hoping you got all of them.
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

# **This script publishes ONE package, and which one is a parameter.** It was written when the Carrier was
# the only NCM plugin, and the id was a module constant used by the drop set, the pruner and the declaration
# alike. A second plugin (Rig Bridge) made that a hazard rather than a simplification: run unchanged for
# another zip and it drops `ncm-carrier` from the declaration and re-adds the new file under the Carrier's
# name, taking Parts and physics off the server in the same breath as it adds force feedback.
#
# The defaults below preserve every existing invocation exactly. `--id` / `--display-name` override them.
PACKAGE_ID = "ncm-carrier"
DISPLAY_NAME = "NCM Carrier"
CAPABILITY = "executable"


# ---------------------------------------------------------------------------------------------- the store

def describe_zip(path):
    """Everything the store metadata needs, read from the archive itself rather than taken on trust."""
    if not zipfile.is_zipfile(path):
        raise SystemExit("%s is not a zip archive" % path)

    with zipfile.ZipFile(path) as archive:
        # Compress-Archive writes Windows separators into ZIP entry names. Warden normalises those before
        # classifying roots; do the same here or a valid red4ext/plugins package is recorded with no roots
        # and its directory entry is counted as a file.
        normalised = [n.replace("\\", "/") for n in archive.namelist()]
        names = [n for n in normalised if not n.endswith("/")]
        bad = archive.testzip()
        if bad:
            raise SystemExit("corrupt entry in archive: %s" % bad)

    # Roots are the first two path segments, which is how the launcher decides whether content is inside a
    # permitted root. `red4ext/plugins` is an EXECUTABLE root -- that is what the consent gate will say.
    roots = sorted({"/".join(n.split("/")[:2]) for n in names if "/" in n})

    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)

    return {
        "sha256": digest.hexdigest(),
        "sizeBytes": os.path.getsize(path),
        "fileCount": len(names),
        "roots": roots,
        "names": names,
    }


def store_blob(server_root, zip_path, version, info):
    store = os.path.join(server_root, ".open77", "mods")
    os.makedirs(store, exist_ok=True)

    blob = os.path.join(store, "%s.blob" % info["sha256"])
    meta = os.path.join(store, "%s.json" % info["sha256"])

    shutil.copy2(zip_path, blob)
    metadata = {
        "id": PACKAGE_ID,
        "version": version,
        "displayName": DISPLAY_NAME,
        "fileName": os.path.basename(zip_path),
        "sha256": info["sha256"],
        "sizeBytes": info["sizeBytes"],
        "capability": CAPABILITY,
        "fileCount": info["fileCount"],
        "roots": info["roots"],
        "importedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "reviewRequestedAtUtc": None,
    }
    with open(meta, "w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent=2)
        fh.write("\n")

    # Read it back. A blob that landed truncated declares a hash the launcher will refuse, and finding that
    # out from a failed join is a much worse afternoon than finding it out here.
    check = hashlib.sha256()
    with open(blob, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            check.update(chunk)
    if check.hexdigest() != info["sha256"]:
        raise SystemExit("blob did not survive the copy -- store is inconsistent, do not restart")

    return blob, meta


def prune_old_blobs(server_root, keep_digest):
    """Remove earlier carrier blobs. The store is content-addressed, so a new build is a new file and the
    old one would sit there forever otherwise."""
    store = os.path.join(server_root, ".open77", "mods")
    removed = []
    if not os.path.isdir(store):
        return removed
    for name in os.listdir(store):
        if not name.endswith(".json"):
            continue
        digest = name[:-5]
        if digest == keep_digest:
            continue
        try:
            with open(os.path.join(store, name), encoding="utf-8") as fh:
                if json.load(fh).get("id") != PACKAGE_ID:
                    continue
        except (OSError, ValueError):
            continue
        for suffix in (".json", ".blob"):
            path = os.path.join(store, digest + suffix)
            if os.path.exists(path):
                os.remove(path)
        removed.append(digest[:12])
    return removed


# ---------------------------------------------------------------------------------- the declaration

def packages_span(text):
    m = re.search(r'("packages"\s*:\s*\[)(.*?)(\n\s*\])', text, re.S)
    if not m:
        raise SystemExit("requiredMods.packages array not found -- is requiredMods configured at all?")
    return m


def split_objects(body):
    """Brace-balanced. server.jsonc writes multi-line objects, and the line-based regexes in
    set-unsecured.py matched nothing against them while reporting success."""
    objs, depth, start = [], 0, None
    for i, ch in enumerate(body):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                objs.append(body[start:i + 1])
    return objs


def id_of(obj):
    m = re.search(r'"id"\s*:\s*"([^"]+)"', obj)
    return m.group(1) if m else None


def head_of(text):
    m = re.search(r'"requiredMods"\s*:\s*\{(.*?)"packages"', text, re.S)
    return " ".join(m.group(1).split()) if m else "(not found)"


def enable_block(text):
    """enabled=true and unsecured=true, inserting `unsecured` if the block never had it."""
    text, enabled = re.subn(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*)false', r'\1true', text, count=1)
    text, unsecured = re.subn(r'("requiredMods"\s*:\s*\{[^}]*?"unsecured"\s*:\s*)false', r'\1true',
                              text, count=1)
    if unsecured == 0 and '"unsecured"' not in head_of(text):
        text = re.sub(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*true)',
                      r'\1,\n    "unsecured": true', text, count=1)
    return text


def set_note(text, note):
    """The note is what a player READS in the consent dialog. Leaving a stale one there is not cosmetic:
    it describes content that is not being offered, next to a request to accept executable code."""
    escaped = note.replace("\\", "\\\\").replace('"', '\\"')
    updated, n = re.subn(r'("requiredMods"\s*:\s*\{[^}]*?"note"\s*:\s*)"[^"]*"',
                         lambda m: m.group(1) + '"' + escaped + '"', text, count=1)
    if n == 0:
        print("WARNING: no requiredMods note field to update")
        return text
    return updated


def backup_and_write(conf, text):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    shutil.copy2(conf, "%s.bak-%s" % (conf, stamp))
    with open(conf, "w", encoding="utf-8") as fh:
        fh.write(text)
    return stamp


# ------------------------------------------------------------------------------------------------- main

def main():
    global PACKAGE_ID, DISPLAY_NAME
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("server_root", nargs="?",
                        default=os.environ.get("NCM_SERVER_ROOT", "/opt/ncm/server"))
    parser.add_argument("--zip", help="the package built by tools/build-carrier.ps1")
    parser.add_argument("--version", help="defaults to the version in the zip's file name")
    parser.add_argument("--enable", action="store_true",
                        help="also set requiredMods enabled=true and unsecured=true")
    parser.add_argument("--import-blob", action="store_true",
                        help="write the blob into the store by hand instead of importing via Warden "
                             "(the server has been observed to prune these; prefer Warden)")
    parser.add_argument("--note", metavar="TEXT",
                        help="the requiredMods note -- players read this at the consent gate")
    parser.add_argument("--drop", action="append", default=[], metavar="ID",
                        help="also remove this package id from the declaration; repeatable")
    parser.add_argument("--remove", action="store_true")
    parser.add_argument("--id", default=PACKAGE_ID, metavar="ID",
                        help="package id to declare and to replace (default: %s)" % PACKAGE_ID)
    parser.add_argument("--display-name", default=None, metavar="TEXT",
                        help="consent-dialog name (default: %s)" % DISPLAY_NAME)
    args = parser.parse_args()

    # Bind the parameterised identity ONCE, before anything reads it. The drop set, the pruner and the
    # declaration all key off these, so they must agree for the whole run.
    if args.id != PACKAGE_ID:
        DISPLAY_NAME = args.display_name or args.id
        PACKAGE_ID = args.id
    elif args.display_name:
        DISPLAY_NAME = args.display_name
    print("publishing package id: %s (%s)" % (PACKAGE_ID, DISPLAY_NAME))

    root = args.server_root
    conf = os.path.join(root, "server.jsonc")
    if not os.path.exists(conf):
        raise SystemExit("no server.jsonc under %s -- wrong server root?" % root)

    print("server root: %s" % os.path.abspath(root))

    with open(conf, "r", encoding="utf-8") as fh:
        text = fh.read()

    m = packages_span(text)
    objs = split_objects(m.group(2))

    # Show and stop.
    if not args.remove and not args.zip:
        print("requiredMods: %s" % head_of(text))
        print("declared: %s" % (", ".join(i or "?" for i in (id_of(o) for o in objs)) or "(none)"))
        for obj in objs:
            if id_of(obj) == PACKAGE_ID:
                print("\n%s:\n%s" % (PACKAGE_ID, obj.strip()))
                return 0
        print("\n%s is NOT declared." % PACKAGE_ID)
        return 0

    # Any previously declared carrier goes, whatever id it was declared under -- an id that changed
    # between imports is exactly how two declarations of the same package end up side by side.
    drop = set(args.drop) | {PACKAGE_ID} | {i for i in (id_of(o) for o in objs)
                                            if i and i.startswith(PACKAGE_ID)}
    kept = [o for o in objs if id_of(o) not in drop]
    dropped = [id_of(o) for o in objs if id_of(o) in drop and id_of(o) != PACKAGE_ID]
    if dropped:
        # Parked packages become REQUIRED again the moment the block is enabled. RB15 in particular must
        # not come back: `L142` ceased its redistribution and `L145` removed it from Production.
        print("dropping from the declaration: %s" % ", ".join(dropped))

    if args.remove:
        if len(kept) == len(objs):
            print("%s was not declared; nothing to do." % PACKAGE_ID)
            return 0
        new_objs = kept
        removed = prune_old_blobs(root, keep_digest="")
        if removed:
            print("removed blob(s): %s" % ", ".join(removed))
    else:
        if not os.path.exists(args.zip):
            raise SystemExit("no such package: %s" % args.zip)
        version = args.version
        if not version:
            m2 = re.search(r"(\d+\.\d+\.\d+)", os.path.basename(args.zip))
            if not m2:
                raise SystemExit("could not read a version from the file name -- pass --version")
            version = m2.group(1)

        info = describe_zip(args.zip)
        print("package: %s v%s" % (os.path.basename(args.zip), version))
        print("  sha256 %s" % info["sha256"])
        print("  %d bytes, %d file(s)" % (info["sizeBytes"], info["fileCount"]))
        print("  roots: %s" % ", ".join(info["roots"]))
        if not any(r.startswith("red4ext/plugins") for r in info["roots"]):
            print("  WARNING: nothing under red4ext/plugins -- the carrier will not load")

        store = os.path.join(root, ".open77", "mods")
        blob = os.path.join(store, "%s.blob" % info["sha256"])
        present = os.path.exists(blob)

        if args.import_blob:
            store_blob(root, args.zip, version, info)
            pruned = prune_old_blobs(root, info["sha256"])
            if pruned:
                print("  pruned older carrier blob(s): %s" % ", ".join(pruned))
            print("  NOTE: hand-written store entries have been pruned by the server on restart.")
            print("        Prefer importing through Warden.")
        elif not present:
            print("")
            print("NOT IN THE STORE. Nothing was changed.")
            print("")
            print("Import it in Warden first -- the store is the server's catalogue, not a drop folder, and")
            print("a hand-written entry gets pruned on the next restart:")
            print("")
            print("  1. open  http://127.0.0.1:11780")
            print("  2. import  %s" % os.path.abspath(args.zip))
            print("  3. run this command again to declare it")
            print("")
            print("Expected sha256 once imported: %s" % info["sha256"])
            return 1
        else:
            print("  blob present in the store")

        # The store entry is authoritative for `id` and `version`. Whoever imported it -- Warden, or an
        # operator following the Production procedure -- decided those, and a declaration that disagrees
        # names a package the server cannot resolve.
        meta_path = os.path.join(store, "%s.json" % info["sha256"])
        try:
            with open(meta_path, encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, ValueError) as exc:
            raise SystemExit("store metadata unreadable (%s): %s" % (meta_path, exc))

        stored_id = meta.get("id")
        stored_version = meta.get("version")
        if not stored_id:
            raise SystemExit("store entry has no id -- re-import it")
        if stored_id != PACKAGE_ID:
            print("  store calls it '%s' (not '%s') -- using the store's id" % (stored_id, PACKAGE_ID))
        if stored_version != version:
            print("  store version is '%s' (zip says '%s') -- using the store's" % (stored_version, version))
        package_id, version = stored_id, stored_version or version

        # **No `capability` here.** It belongs in the store metadata and ONLY there:
        # `RequiredModConfiguration` has no such member and the server refuses to start with it present --
        # "The JSON property 'capability' could not be mapped to any .NET member". Learned the hard way on
        # 2026-09-25; `configure-required-mods-https.py` already filtered it out and this script did not.
        entry = {
            "id": package_id,
            "source": "hosted",
            "displayName": DISPLAY_NAME,
            "version": version,
            "sha256": info["sha256"],
            "sizeBytes": info["sizeBytes"],
        }
        new_objs = kept + [json.dumps(entry, indent=2)]

    indent = "\n      "
    body = indent + ("," + indent).join(o.strip() for o in new_objs) if new_objs else "\n      "
    updated = text[:m.start()] + m.group(1) + body + m.group(3) + text[m.end():]

    if args.enable and not args.remove:
        updated = enable_block(updated)
    if args.note:
        updated = set_note(updated, args.note)

    stamp = backup_and_write(conf, updated)
    print("\nbackup: server.jsonc.bak-%s" % stamp)
    print("requiredMods: %s" % head_of(updated))
    print("declared: %s" % (", ".join(id_of(o) or "?" for o in new_objs) or "(none)"))
    if args.enable and not args.remove:
        others = [id_of(o) for o in new_objs if id_of(o) != PACKAGE_ID]
        if others:
            print("\nNOTE: enabling makes ALL of these required to join: %s" % ", ".join(others))
        else:
            print("\nThe carrier is the only required package. RED4ext itself is not hosted here -- it is")
            print("already installed in the game, which is how ArchiveXL and TweakXL load today.")

    print("\nRESTART THE SERVER, then check the manifest digest changed:")
    print("  curl -s http://127.0.0.1:11779/mods/v1/manifest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
