"""Offline tests for the astronomical substrate (doc 57 §4): real Lua 5.4 via lupa, the LIVE ncm-core loader
(init.lua pulled from the server) plus the new modules. Read-only: the Galena/Hella states come from a local
snapshot of ncm_presence (deep_full.tsv); nothing here talks to the server.

Usage: python tests/run.py
"""
import json
import os
import sys

import lupa.lua54 as L

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LIVE_CORE = os.path.join(REPO, "ncm", "core")
NEW = os.path.join(REPO, "ncm", "core", "space")
SNAP = os.path.expanduser(os.path.join("~", "deep_full.tsv"))

lua = L.LuaRuntime(unpack_returned_tuples=True)
STARS = os.path.join(NEW, "stars")
for path in [os.path.join(LIVE_CORE, "init.lua"), os.path.join(LIVE_CORE, "vocabulary", "json.lua")] + [os.path.join(NEW, f) for f in (
        "astro.lua", "data_solar.lua", "ephemeris.lua", "catalogue.lua", "gravity.lua", "frames.lua", "telemetry.lua")] \
        + sorted(os.path.join(STARS, f) for f in os.listdir(STARS)):
    lua.execute(open(path, encoding="utf-8").read())

lua.execute(open(os.path.join(HERE, "substrate_tests.lua"), encoding="utf-8").read())

snap = {}
if os.path.exists(SNAP):
    for line in open(SNAP, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) == 4 and f[3].startswith("{"):
            s = json.loads(f[3])
            snap[s["vehicleKey"]] = f[3]
lua.globals().SNAP = lua.table_from(snap)
ok = lua.eval("RUN_TESTS()")
sys.exit(0 if ok else 1)
