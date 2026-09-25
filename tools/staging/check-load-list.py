#!/usr/bin/env python3
"""Post-upgrade guard: every dependency of a loaded resource must itself be in resources.load.

RUN THIS AFTER EVERY OPEN//77 UPGRADE, BEFORE RESTARTING.

`resources.load` in server.jsonc is an explicit ALLOW-LIST, not a directory scan. When an upgrade adds a new
resource and makes an already-loaded one depend on it, the new resource is never loaded, and the server reports:

    [ERR] Automatic resource start failed: Resource '<name>' was not found.

That aborts the WHOLE automatic start set. The server still comes up, listens, and registers with the master --
so it looks healthy -- while NCM is silently absent. That is exactly what .84 -> .87 did with
`open77_cyberware_lab`, which .87 added and made `freeroam` depend on (KB-51).

Exit codes: 0 clean, 1 missing dependencies found, 2 could not inspect.
Never prints server.jsonc (it holds the licence key) -- only resource names.
"""
import os
import re
import sys

# The server root is a parameter so this guard runs on BOTH sides. It was written for Lightsail,
# but the whole point of the Windows development box is that a change is instrumented there first
# -- a guard that only runs in production is a guard that runs too late.
#   python3 check-load-list.py [server-root]      (default: the Lightsail layout)
SERVER = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("NCM_SERVER_ROOT", "/opt/ncm/server")
CONF = os.path.join(SERVER, "server.jsonc")
ROOT = os.path.join(SERVER, "resources")


def load_list():
    """Resource names in resources.load, read without echoing the file."""
    with open(CONF, "r", encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r'"load"\s*:\s*\[(.*?)\]', text, re.S)
    if not m:
        return None
    # **Match any quoted entry, not just [A-Za-z0-9_]+.** Load entries may be globs -- `ncm/*` is how every
    # NCM resource is loaded -- and the narrower class silently dropped exactly that one. A guard whose whole
    # purpose is "did NCM fail to load" could not see NCM's own line (2026-09-25).
    return set(re.findall(r'"([^"]+)"', m.group(1)))


def manifests():
    """{resource name: (path, declared dependency names)} for every open77.lua under resources/."""
    out = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        if "open77.lua" not in filenames:
            continue
        path = os.path.join(dirpath, "open77.lua")
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        # Manifests use single OR double quotes -- open77_animations and open77_player_interactions use
        # single, everything else uses double. Matching only one kind makes this guard report false missing
        # resources, and a guard that cries wolf gets ignored.
        nm = re.search(r"""^\s*resource\s+['"]([^'"]+)['"]""", text, re.M)
        if not nm:
            continue
        deps = set(re.findall(r"""^\s*dependency\s+['"]([A-Za-z0-9_]+)""", text, re.M))
        for block in re.findall(r"dependencies\s*\{(.*?)\}", text, re.S):
            deps |= set(re.findall(r"""['"]([A-Za-z0-9_]+)""", block))
        out[nm.group(1)] = (path, deps)
    return out


def main():
    if not os.path.exists(CONF) or not os.path.isdir(ROOT):
        print("cannot inspect: %s or %s missing" % (CONF, ROOT))
        return 2

    loaded = load_list()
    if loaded is None:
        print("could not find resources.load in server.jsonc")
        return 2

    found = manifests()
    known = set(found)
    problems = []

    # A glob entry such as `ncm/*` names a DIRECTORY of resources rather than one resource. Expand it to
    # whatever manifests live under that directory, and say so when it expands to nothing -- an empty glob is
    # the silent way a whole subsystem goes missing.
    expanded, globs = set(), [n for n in loaded if "*" in n or "/" in n]
    for g in globs:
        base = g.split("*")[0].rstrip("/")
        prefix = os.path.join(ROOT, base.replace("/", os.sep))
        hits = {nm for nm, (p, _) in found.items() if p.startswith(prefix + os.sep)}
        if not hits:
            problems.append(("glob matches nothing on disk", g, "", base))
        expanded |= hits
    loaded = (loaded - set(globs)) | expanded

    for name in sorted(loaded):
        path, deps = found.get(name, (None, set()))
        if path is None:
            problems.append(("listed but not on disk", name, "", ""))
            continue
        for dep in sorted(deps):
            if dep not in loaded:
                where = "present on disk" if dep in known else "NOT ON DISK"
                problems.append(("dependency not in load list", name, dep, where))

    # The KB-51 question, asked directly instead of inferred. A server with every dependency satisfied and
    # no NCM is exactly the failure this file exists to prevent, and it looks perfectly healthy.
    ncm = sorted(n for n in loaded if n.startswith("ncm_"))
    if not ncm:
        problems.append(("NCM IS NOT IN THE LOAD LIST", "ncm/*", "", "the server will run without NCM"))

    if not problems:
        print("load list OK: %d resources, every dependency satisfied" % len(loaded))
        print("NCM resources loaded: %s" % ", ".join(ncm))
        return 0

    print("PROBLEMS FOUND (%d) -- the server will abort its automatic start set:" % len(problems))
    for kind, name, dep, where in problems:
        if dep:
            print("  %-28s %s -> %s (%s)" % (kind, name, dep, where))
        else:
            print("  %-28s %s" % (kind, name))
    print("")
    print("Fix: add the missing name(s) to resources.load in server.jsonc, after their own dependencies.")
    print("See tools/staging/add-cyberware-lab.py for the shape of that edit.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
