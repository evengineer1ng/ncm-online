# Staging only: turn on requiredMods.unsecured (executable packages install after the player's consent)
# and drop the indexed archivexl/tweakxl entries (NotInIndex on the alpha master; they are hosted via Warden instead).
# Run on the box: python3 set-unsecured.py && sudo systemctl restart ncm-server. Never prints the licence.
import re
p = "/opt/ncm/server/server.jsonc"; s = open(p).read()
s = re.sub(r'\n\s*\{ "id": "archivexl", "minVersion": "[^"]+" \},', '', s)
s = re.sub(r'\n\s*\{ "id": "tweakxl", "minVersion": "[^"]+" \},', '', s)
m = re.search(r'("requiredMods"\s*:\s*\{\s*"enabled"\s*:\s*true)(\s*,\s*"unsecured"\s*:\s*(true|false))?', s)
assert m, "requiredMods block not found"
s = s[:m.start()] + m.group(1) + ',\n    "unsecured": true' + s[m.end():]
open(p, "w").write(s)
head = re.search(r'"requiredMods"\s*:\s*\{(.*?)"packages"', s, re.S).group(1)
print("requiredMods head:", " ".join(head.split()))
print("packages:", re.findall(r'"id"\s*:\s*"([^"]+)"', re.search(r'"packages"\s*:\s*\[(.*?)\n\s*\]', s, re.S).group(1)))
