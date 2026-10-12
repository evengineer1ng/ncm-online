#!/usr/bin/env python3
"""Assemble the ncm_universe resource (doc 57 §5) from the core modules: copies the LIVE core loader (init.lua) and
JSON vocabulary, the substrate modules and the star chunks under resources/ncm_universe/core/, and writes open77.lua
with every file as a SERVER script (players never download the star catalogue). Output: dist/ncm_universe.tgz.
"""
import os
import shutil
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "resources", "ncm_universe")
LIVE = os.path.join(ROOT, "live", "ncm_world", "shared", "core")
NEW = os.path.join(ROOT, "core", "space")

core_dir = os.path.join(RES, "core")
shutil.rmtree(core_dir, ignore_errors=True)
os.makedirs(os.path.join(core_dir, "stars"))
files = []
for src, rel in ((os.path.join(LIVE, "init.lua"), "core/init.lua"),
                 (os.path.join(LIVE, "vocabulary", "json.lua"), "core/json.lua")):
    shutil.copyfile(src, os.path.join(RES, rel)); files.append(rel)
for name in ("astro", "data_solar", "ephemeris", "catalogue", "gravity", "frames", "telemetry"):
    rel = "core/%s.lua" % name
    shutil.copyfile(os.path.join(NEW, name + ".lua"), os.path.join(RES, rel)); files.append(rel)
for name in sorted(os.listdir(os.path.join(NEW, "stars"))):
    rel = "core/stars/" + name
    shutil.copyfile(os.path.join(NEW, "stars", name), os.path.join(RES, rel)); files.append(rel)

with open(os.path.join(RES, "open77.lua"), "w", encoding="utf-8", newline="\n") as f:
    f.write('-- ncm_universe -- the astronomical substrate on the server, SHADOW MODE (doc 57 §5): read-only; it never writes\n')
    f.write('-- a Deep record or changes how anything flies. Star data: Hipparcos (ESA, van Leeuwen 2007, CDS I/311).\n')
    f.write('resource "ncm_universe"\nversion "0.1.0"\nauto_start true\n\n')
    f.write('permissions { "database.access", "network.events" }\n\n')
    for rel in files:
        f.write('server_script "%s"\n' % rel)
    f.write('server_script "server/main.lua"\n')

os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
out = os.path.join(ROOT, "dist", "ncm_universe.tgz")
with tarfile.open(out, "w:gz") as t:
    for dirpath, _, names in os.walk(RES):
        for n in names:
            p = os.path.join(dirpath, n)
            t.add(p, arcname=os.path.relpath(p, RES).replace(os.sep, "/"))
print("files:", len(files) + 1, "->", out, os.path.getsize(out), "bytes")
