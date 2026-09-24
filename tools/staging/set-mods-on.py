# Staging: un-park required mods (enabled=true, unsecured=true) to re-test KB-8 against the master's verdicts.
# The exact mirror of set-mods-off.py. Run on the box: python3 set-mods-on.py && sudo systemctl restart ncm-server.
# Never prints the licence.
#
# WHY THIS EXISTS: set-unsecured.py only ADDS "unsecured" to a block that is ALREADY enabled --
#   m = re.search(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*true)...'); assert m
# -- so it aborts on its own assert when the block is parked (enabled=false), which is the state
# set-mods-off.py leaves behind. Use this to go from parked -> testing, and set-mods-off.py to park again.
#
# ALWAYS PARK AGAIN AFTER TESTING. While this is on and KB-8 stands, ordinary launcher joins are refused.
import re

p = "/opt/ncm/server/server.jsonc"
s = open(p).read()

before = re.search(r'"requiredMods"\s*:\s*\{(.*?)"packages"', s, re.S)
assert before, "requiredMods block not found"

s, n_en = re.subn(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*)false', r'\1true', s, count=1)
s, n_un = re.subn(r'("requiredMods"\s*:\s*\{[^}]*?"unsecured"\s*:\s*)false', r'\1true', s, count=1)

# if "unsecured" was absent entirely, insert it right after enabled (what set-unsecured.py would have done)
if n_un == 0 and '"unsecured"' not in before.group(1):
    s = re.sub(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*true)',
               r'\1,\n    "unsecured": true', s, count=1)
    n_un = 1

open(p, "w").write(s)
head = re.search(r'"requiredMods"\s*:\s*\{(.*?)"packages"', s, re.S).group(1)
print("enabled flipped:", n_en, " unsecured set:", n_un)
print("requiredMods head:", " ".join(head.split()))
