#!/usr/bin/env python3
"""Declare (or update, or remove) the NCM Carrier package in requiredMods.packages.

    python3 declare-carrier.py <server-root> --version 0.1.0 --sha256 <hex> --size <bytes>
    python3 declare-carrier.py <server-root> --remove
    python3 declare-carrier.py <server-root>                      # show what is declared

The server root is a PARAMETER, not a constant (`KB-120`). The whole point of the Windows development box
is that a change is instrumented there first; a script that can only address Production is a script that
runs too late. Default is the Lightsail layout, so Production still needs no argument -- and therefore
**pass the development root explicitly and check what you passed.**

NEVER PRINTS THE LICENCE. server.jsonc holds it, so this reads the file and prints only package fields.

Brace-balanced editing, copied from drop-loader-mods.py, because the naive one-line regexes in
set-unsecured.py silently matched nothing against the multi-line objects server.jsonc actually writes -- and
then reported success. A config editor that lies about editing is worse than one that refuses.

AFTER RUNNING: restart the server, then confirm the manifest digest changed:
    curl -s http://127.0.0.1:11779/mods/v1/manifest
"""
import argparse
import datetime
import json
import os
import re
import shutil
import sys

PACKAGE_ID = "ncm-carrier"


def load(conf):
    with open(conf, "r", encoding="utf-8") as fh:
        return fh.read()


def packages_span(text):
    """The requiredMods.packages array, as (start, end, head, body, tail)."""
    m = re.search(r'("packages"\s*:\s*\[)(.*?)(\n\s*\])', text, re.S)
    if not m:
        raise SystemExit("requiredMods.packages array not found -- is requiredMods configured at all?")
    return m


def split_objects(body):
    """Brace-balanced split. server.jsonc writes multi-line objects; line-based splitting loses them."""
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


def write(conf, text):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    shutil.copy2(conf, "%s.bak-%s" % (conf, stamp))
    with open(conf, "w", encoding="utf-8") as fh:
        fh.write(text)
    return stamp


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("server_root", nargs="?",
                        default=os.environ.get("NCM_SERVER_ROOT", "/opt/ncm/server"))
    parser.add_argument("--version")
    parser.add_argument("--sha256")
    parser.add_argument("--size", type=int)
    parser.add_argument("--remove", action="store_true")
    args = parser.parse_args()

    conf = os.path.join(args.server_root, "server.jsonc")
    if not os.path.exists(conf):
        raise SystemExit("no server.jsonc under %s -- wrong server root?" % args.server_root)

    text = load(conf)
    m = packages_span(text)
    head, body, tail = m.group(1), m.group(2), m.group(3)
    objs = split_objects(body)
    ids = [id_of(o) for o in objs]

    # Show and stop.
    if not args.remove and not (args.version and args.sha256 and args.size):
        print("server root: %s" % args.server_root)
        print("declared packages: %s" % ", ".join(i or "?" for i in ids))
        for obj in objs:
            if id_of(obj) == PACKAGE_ID:
                print("\n%s is declared as:\n%s" % (PACKAGE_ID, obj.strip()))
                return
        print("\n%s is NOT declared." % PACKAGE_ID)
        return

    kept = [o for o in objs if id_of(o) != PACKAGE_ID]
    removed = len(objs) - len(kept)

    if args.remove:
        if removed == 0:
            print("%s was not declared; nothing to do." % PACKAGE_ID)
            return
        new_objs = kept
    else:
        if not re.fullmatch(r"[0-9a-f]{64}", args.sha256 or ""):
            raise SystemExit("--sha256 must be 64 lowercase hex characters")
        if args.size <= 0:
            raise SystemExit("--size must be the blob's real byte count")
        entry = {
            "id": PACKAGE_ID,
            "source": "hosted",
            "displayName": "NCM Carrier",
            "version": args.version,
            "sha256": args.sha256,
            "sizeBytes": args.size,
            # Executable, and the consent gate will say so in exactly those words. A player accepting this
            # is accepting native code NCM wrote, on an unsecured world. That is the honest framing and it
            # is the reason this is not called anything softer.
            "capability": "executable",
        }
        new_objs = kept + [json.dumps(entry, indent=2)]

    indent = "\n      "
    new_body = indent + ("," + indent).join(o.strip() for o in new_objs) if new_objs else "\n      "
    updated = text[:m.start()] + head + new_body + tail + text[m.end():]

    stamp = write(conf, updated)
    print("backup: server.jsonc.bak-%s" % stamp)
    print("packages now: %s" % ", ".join(id_of(o) or "?" for o in new_objs))
    print("\nRESTART THE SERVER, then check the manifest digest changed.")


if __name__ == "__main__":
    sys.exit(main())
