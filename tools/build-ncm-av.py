"""Package NCM AV (ncm/av/pack) as dist/ncm-av-<version>.zip, laid out as the game folder."""
import hashlib, os, sys, zipfile

VERSION = "0.1.1"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pack = os.path.join(root, "ncm", "av", "pack")
out = os.path.join(root, "dist", "ncm-av-%s.zip" % VERSION)
os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(pack):
        for f in sorted(files):
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, pack).replace(os.sep, "/"))
print(out)
print("sha256", hashlib.sha256(open(out, "rb").read()).hexdigest())
print(zipfile.ZipFile(out).namelist())
