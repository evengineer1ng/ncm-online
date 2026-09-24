#!/usr/bin/env python3
"""Add open77_cyberware_lab to server.jsonc's resources.load allow-list (.87 upgrade fix).

WHY: `resources.load` is an explicit allow-list, not a directory scan. Open//77 .87 makes the shipped
`freeroam` gamemode depend on `open77_cyberware_lab >=0.1.0` (gamemodes/freeroam/open77.lua), and the lab is a
new resource in .87 that no .84 config could have listed. A dependency on a resource that was never loaded is
reported as:

    [ERR] Automatic resource start failed: Resource 'open77_cyberware_lab' was not found.

That aborts the WHOLE automatic start set, so NCM never starts either -- the server comes up, registers with the
master and listens, while ncm_world/ncm_league are silently absent.

Inserted immediately after open77_reflex, because the lab declares `dependency open77_equipment / open77_dash /
open77_reflex` and all three appear earlier in the list.

Idempotent: running it twice changes nothing. Never prints the file (it holds the licence key).
"""
import datetime
import os
import re
import shutil
import sys

PATH = "/opt/ncm/server/server.jsonc"
ENTRY = "open77_cyberware_lab"
ANCHOR = "open77_reflex"


def main():
    if not os.path.exists(PATH):
        print("server.jsonc not found at %s" % PATH)
        return 2

    with open(PATH, "r", encoding="utf-8") as fh:
        lines = fh.readlines()

    if any(ENTRY in ln for ln in lines):
        print("already present: %s (no change)" % ENTRY)
        return 0

    anchor_ix = None
    for i, ln in enumerate(lines):
        if re.search(r'"%s"\s*,' % re.escape(ANCHOR), ln):
            anchor_ix = i
            break
    if anchor_ix is None:
        print("anchor %s not found in the load list; refusing to guess a position" % ANCHOR)
        return 3

    indent = re.match(r"\s*", lines[anchor_ix]).group(0)
    backup = "%s.bak-%s" % (PATH, datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ"))
    shutil.copy2(PATH, backup)

    lines.insert(anchor_ix + 1, '%s"%s",\n' % (indent, ENTRY))
    with open(PATH, "w", encoding="utf-8") as fh:
        fh.writelines(lines)

    print("inserted %s after %s (backup: %s)" % (ENTRY, ANCHOR, os.path.basename(backup)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
