"""Run ncm/core/tests/run.lua under Lua 5.4 and LuaJIT 2.1 through lupa (this VM has no standalone Lua).

    python -I tools/deep/tests/core_run.py [filter]

Exit code 1 if either runtime reports a failure."""
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
CORE = os.path.join(REPO, "ncm", "core").replace("\\", "/")
FILTER = sys.argv[1] if len(sys.argv) > 1 else None


def run(modname):
    try:
        mod = __import__("lupa." + modname, fromlist=["LuaRuntime"])
    except ImportError:
        print("== %s: not available" % modname)
        return True
    lua = mod.LuaRuntime(unpack_returned_tuples=True)
    exit_code = {"v": 0}

    def _exit(code=0, *_):
        if code is True:
            code = 0
        elif code is False:
            code = 1
        exit_code["v"] = int(code or 0)
        raise SystemExit

    lua.globals().os.exit = _exit
    arg = lua.table(CORE, FILTER) if FILTER else lua.table(CORE)
    lua.globals().arg = arg
    try:
        lua.execute(open(os.path.join(CORE, "tests", "run.lua"), encoding="utf-8").read())
    except SystemExit:
        pass
    ok = exit_code["v"] == 0
    print("== %s: %s" % (modname, "PASS" if ok else "FAIL"))
    return ok


ok = all([run("lua54"), run("luajit21")])
sys.exit(0 if ok else 1)
