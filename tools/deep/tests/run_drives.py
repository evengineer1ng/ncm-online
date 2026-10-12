import sys, os, harness
STARS = "--client" not in sys.argv
lua = harness.runtime(stars=STARS)
print("mode:", "server (full star catalogue)" if STARS else "client (no star catalogue: nav set only)")
lua.execute('NcmCore.get("space.catalogue").loadAll()')
ok = lua.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests_drives.lua"), encoding="utf-8").read())
sys.exit(0 if ok else 1)
