#!/usr/bin/env python3
"""Pack NCM Gearbox (package `ncm-gearbox`) into dist/ncm-gearbox-<version>.zip, laid out over the game folder.

    python ncm/gearbox/pack.py            # after: lua tools/gen-gearbox-records.lua; cmake --build ncm/gearbox/build --config Release

Phase 0 (L306): dev only, installed with `python tools/dev-hand-install-mods.py --only none --extra-zip <zip>`;
`--uninstall` removes it. Not declared by any server until the spike passes.
"""
import os
import re
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
version = re.search(r"project\(ncm_gearbox VERSION ([0-9.]+)", open(os.path.join(HERE, "CMakeLists.txt")).read()).group(1)
files = {
    "red4ext/plugins/ncm_gearbox/ncm_gearbox.dll": os.path.join(HERE, "build", "Release", "ncm_gearbox.dll"),
    "red4ext/plugins/ncm_gearbox/ncm_gearbox_specs.json": os.path.join(HERE, "data", "ncm_gearbox_specs.json"),
    "r6/tweaks/ncm_gearbox/clones.yaml": os.path.join(HERE, "r6", "tweaks", "ncm_gearbox", "clones.yaml"),
    # phase 3a (S2): the census/observe/hold config and the redscript that feeds the DLL the player's car
    "red4ext/plugins/ncm_gearbox/ncm_gearbox_config.json": os.path.join(HERE, "data", "ncm_gearbox_config.json"),
    "r6/scripts/ncm_gearbox/NcmGearbox.reds": os.path.join(HERE, "r6", "scripts", "ncm_gearbox", "NcmGearbox.reds"),
    "r6/scripts/ncm_gearbox/NcmGearboxNatives.reds": os.path.join(HERE, "r6", "scripts", "ncm_gearbox", "NcmGearboxNatives.reds"),
    "r6/scripts/ncm_gearbox/NcmGearboxDash.reds": os.path.join(HERE, "r6", "scripts", "ncm_gearbox", "NcmGearboxDash.reds"),
}
out = os.path.join(REPO, "dist", "ncm-gearbox-%s.zip" % version)
os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, src in files.items():
        if not os.path.exists(src):
            raise SystemExit("missing " + src)
        z.write(src, name)
print("packed %s (%d files)" % (out, len(files)))
