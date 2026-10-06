#!/usr/bin/env python3
"""Pack NCM Thrust (package `ncm-thrust`) into dist/ncm-thrust-<version>.zip, laid out over the game folder.

    cmake --preset release -S ncm/thrust; cmake --build ncm/thrust/build --config Release; python ncm/thrust/pack.py

L316 F0: dev only, installed with `python tools/dev-hand-install-mods.py --only none --extra-zip <zip>`;
`--uninstall` removes it. Needs NCM Carrier 0.1.33+ (the lift lever's consumer). Never declared by a server.
"""
import os
import re
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
version = re.search(r"project\(ncm_thrust VERSION ([0-9.]+)", open(os.path.join(HERE, "CMakeLists.txt")).read()).group(1)
files = {
    "red4ext/plugins/ncm_thrust/ncm_thrust.dll": os.path.join(HERE, "build", "Release", "ncm_thrust.dll"),
    "red4ext/plugins/ncm_thrust/ncm_thrust_config.json": os.path.join(HERE, "data", "ncm_thrust_config.json"),
}
out = os.path.join(REPO, "dist", "ncm-thrust-%s.zip" % version)
os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, src in files.items():
        if not os.path.exists(src):
            raise SystemExit("missing " + src)
        z.write(src, name)
print("packed %s (%d files)" % (out, len(files)))
