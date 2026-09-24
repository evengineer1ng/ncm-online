# Staging: park required mods (enabled=false, unsecured=false) so plain launcher joins work while hosted mods
# are non-functional on the alpha master (KNOWN_BUGS KB-8). Packages stay declared/imported; flip enabled back
# to true (and re-run set-unsecured.py if loaders are hosted) when the platform can attest hosted hashes.
import re
p = "/opt/ncm/server/server.jsonc"; s = open(p).read()
s = re.sub(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*)true', r'\1false', s, count=1)
s = re.sub(r'("requiredMods"\s*:\s*\{[^}]*?"unsecured"\s*:\s*)true', r'\1false', s, count=1)
open(p, "w").write(s)
head = re.search(r'"requiredMods"\s*:\s*\{(.*?)"packages"', s, re.S).group(1)
print("requiredMods head:", " ".join(head.split()))
