"""Doc 60/61 offline harness: ncm_world's ncm-core, loaded in manifest order under Lua 5.4 (lupa), with the
Hipparcos star chunks. Read-only; talks to nothing. Run from anywhere: paths are relative to the repo."""
import os, re
import lupa.lua54 as L

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
WORLD = os.path.join(REPO, "ncm", "online", "resources", "ncm_world")
STARS = os.path.join(REPO, "ncm", "core", "space", "stars")

def runtime(stars=True, navstars=True, overlay=True):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    man = open(os.path.join(WORLD, "open77.lua"), encoding="utf-8").read()
    for f in re.findall(r'^shared_script "([^"]+)"', man, re.M):
        if not navstars and f.endswith("data_navstars.lua"):
            continue
        lua.execute(open(os.path.join(WORLD, f), encoding="utf-8").read())
    if stars:
        for f in sorted(os.listdir(STARS)):
            lua.execute(open(os.path.join(STARS, f), encoding="utf-8").read())
    return lua
