# Staging: park required mods (enabled=false, unsecured=false). Packages stay declared/imported; flip enabled
# back to true with set-mods-on.py when there is content to deliver.
#
# ORIGINALLY written for KB-8 ("hosted mods are non-functional on the alpha master"). That diagnosis is
# superseded: KB-112 found the real cause -- launchers .89/.100 sanitize every non-loopback http: mod URL to
# null and then misreport the missing URL as Unverifiable -- and the Online HTTPS origin cleared it. L141
# records a live owner join that consented, downloaded, projected, booted and entered the world. Parking is
# therefore no longer a workaround for a broken pipeline; it is a deliberate "we have nothing to declare".
#
# THE SERVER ROOT IS A PARAMETER, for the same reason check-load-list.py takes one: a tool that can only
# address production is a tool that cannot instrument the Windows development box first, and this project's
# standing rule is that Windows dev is instrumented before any Lightsail change. Hardcoding /opt/ncm left the
# Development side with no tool at all, and the house rule forbids hand-editing server.jsonc (it holds the
# licence key). Default is unchanged, so every existing production invocation still works.
#
#   python3 set-mods-off.py                          # Lightsail default: /opt/ncm/server
#   python  set-mods-off.py tools/open77/server      # Windows development
#
# Then restart that server. Never prints the licence: only the requiredMods head and the package ids.
import os
import re
import shutil
import sys
import time

SERVER = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("NCM_SERVER_ROOT", "/opt/ncm/server")
CONF = os.path.join(SERVER, "server.jsonc")

if not os.path.isfile(CONF):
    print("no server.jsonc under %s" % SERVER)
    raise SystemExit(2)

s = open(CONF).read()
if not re.search(r'"requiredMods"\s*:\s*\{', s):
    print("no requiredMods block in %s -- nothing to park" % CONF)
    raise SystemExit(2)

# Back up before writing. The Online change of 2026-09-25 kept a timestamped copy under /opt/ncm/backups and
# that is the only reason its previous state is recoverable; the same courtesy costs nothing here.
backup = "%s.%s.bak" % (CONF, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
shutil.copy2(CONF, backup)

s, n_en = re.subn(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*)true', r'\1false', s, count=1)
s, n_un = re.subn(r'("requiredMods"\s*:\s*\{[^}]*?"unsecured"\s*:\s*)true', r'\1false', s, count=1)
open(CONF, "w").write(s)

head = re.search(r'"requiredMods"\s*:\s*\{(.*?)"packages"', s, re.S)
pkgs = re.search(r'"packages"\s*:\s*\[(.*?)\n\s*\]', s, re.S)
print("server root      :", SERVER)
print("backup           :", os.path.basename(backup))
print("enabled cleared  :", n_en, " unsecured cleared:", n_un)
if head:
    print("requiredMods head:", " ".join(head.group(1).split()))
if pkgs:
    print("packages still declared:", re.findall(r'"id"\s*:\s*"([^"]+)"', pkgs.group(1)))
print("restart this server for the change to take effect.")
