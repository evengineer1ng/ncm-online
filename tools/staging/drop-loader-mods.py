# Staging: remove the archivexl / tweakxl package entries from requiredMods.packages.
#
# WHY: KB-8 testing has always declared FOUR packages -- our two reviewed NCM archives plus the two third-party
# loaders. The loaders are self-hosted blobs (`source: "hosted"`) that were never submitted for review, so they
# can never be attested, and ONE refused package fails the whole join. Every "still Unverifiable" result since
# 2026-09-20 therefore tested a configuration that could not pass, and told us nothing about whether OUR reviews
# landed.
#
# set-unsecured.py intended to do this and silently did not: its regexes assume one-line entries
#     \n\s*\{ "id": "archivexl", "minVersion": "..." \},
# while server.jsonc writes multi-line objects, so re.sub matched nothing and printed success anyway.
#
# This removes whole brace-balanced objects whose "id" matches, with the trailing comma, and reports what it did.
# Restores are easy: server.jsonc.bak-<UTC> is written first. Never prints the licence.
import datetime
import re
import shutil

P = "/opt/ncm/server/server.jsonc"
DROP = {"archivexl", "tweakxl"}

s = open(P).read()
m = re.search(r'("packages"\s*:\s*\[)(.*?)(\n\s*\])', s, re.S)
assert m, "requiredMods.packages array not found"
head, body, tail = m.group(1), m.group(2), m.group(3)

# split the array body into brace-balanced objects
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

kept, dropped = [], []
for o in objs:
    idm = re.search(r'"id"\s*:\s*"([^"]+)"', o)
    name = idm.group(1) if idm else "?"
    (dropped if name in DROP else kept).append(name if name else "?")

if not dropped:
    print("nothing to drop; packages =", kept)
else:
    shutil.copy2(P, "%s.bak-%s" % (P, datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")))
    keep_objs = [o for o in objs if (re.search(r'"id"\s*:\s*"([^"]+)"', o) or [None]) and
                 re.search(r'"id"\s*:\s*"([^"]+)"', o).group(1) not in DROP]
    indent = "\n      "
    new_body = indent + ("," + indent).join(x.strip() for x in keep_objs)
    s = s[:m.start()] + head + new_body + tail + s[m.end():]
    open(P, "w").write(s)
    print("dropped:", dropped)
    print("kept:", kept)
