from pathlib import Path


paths = (
    Path("/opt/ncm/server/server.jsonc"),
    Path("/opt/ncm/server/templates/freeroam/template.json"),
)

changed = []
for path in paths:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    filtered = [line for line in lines if '"open77_cyberware_lab"' not in line]
    if filtered != lines:
        path.write_text("".join(filtered), encoding="utf-8")
        changed.append(str(path))

if changed:
    print("removed undiscoverable optional open77_cyberware_lab from: " + ", ".join(changed))
else:
    print("open77_cyberware_lab already absent from server config and freeroam template")
