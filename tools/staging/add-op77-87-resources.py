from pathlib import Path


path = Path("/opt/ncm/server/server.jsonc")
text = path.read_text(encoding="utf-8")
anchor = '      "open77_cyberware",\n'
required = ('open77_dash', 'open77_reflex')

if all(f'"{name}"' in text for name in required):
    print("op77.87 resource dependencies already present")
elif anchor not in text:
    raise SystemExit("open77_cyberware load entry not found; configuration unchanged")
else:
    addition = ''.join(f'      "{name}",\n' for name in required if f'"{name}"' not in text)
    path.write_text(text.replace(anchor, anchor + addition, 1), encoding="utf-8")
    print("added op77_dash and open77_reflex to resources.load")
