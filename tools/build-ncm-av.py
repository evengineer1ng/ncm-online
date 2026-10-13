"""Package NCM AV as dist/ncm-av-<version>.zip, laid out as the game folder.

  archive/pc/mod/ncm_av.archive     ncm\\av\\atlus (the car-class Atlus entity + appearances) and ncm\\av\\vfx, built from
                                    ncm/av/source (WolvenKit JSON) with WolvenKit 8.20: convert deserialize, then pack
  r6/tweaks/ncm_av/atlus.yaml       Vehicle.ncm_atlus_av
  r6/tweaks/ncm_av/CREDITS.txt      Drive an Aerial Vehicle's MIT licence (the entity is derived from DAV's)
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

VERSION = "0.2.0"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
av = os.path.join(root, "ncm", "av")
wk = os.path.join(root, "tools", "WolvenKit.Console-8.20.0", "WolvenKit.CLI.exe")
out = os.path.join(root, "dist", "ncm-av-%s.zip" % VERSION)

work = tempfile.mkdtemp(prefix="ncm-av-")
src = os.path.join(work, "ncm_av")
shutil.copytree(os.path.join(av, "source"), src)
r = subprocess.run([wk, "convert", "deserialize", src], capture_output=True, text=True)
for base, _, files in os.walk(src):
    for f in files:
        if f.endswith(".json"):
            os.remove(os.path.join(base, f))
built = sorted(os.path.relpath(os.path.join(b, f), src) for b, _, fs in os.walk(src) for f in fs)
if len(built) != 4:
    sys.exit("deserialize produced %r\n%s" % (built, r.stdout[-2000:]))
packed = os.path.join(work, "packed")
subprocess.run([wk, "pack", src, "-o", packed], check=True, capture_output=True)
archive = os.path.join(packed, "ncm_av.archive")
if not os.path.isfile(archive):
    sys.exit("pack produced no ncm_av.archive")

os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(archive, "archive/pc/mod/ncm_av.archive")
    pack = os.path.join(av, "pack")
    for base, _, files in os.walk(pack):
        for f in sorted(files):
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, pack).replace(os.sep, "/"))
shutil.rmtree(work, ignore_errors=True)
print(out)
print("sha256", hashlib.sha256(open(out, "rb").read()).hexdigest())
print("built", built)
print(zipfile.ZipFile(out).namelist())
