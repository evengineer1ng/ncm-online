"""The Hella's body for Kitten Space Agency, made from the player's OWN Cyberpunk 2077 files (L336).

The same Machine reaches deep space visibly: KSA flies an NCM craft whose body is the Archer Hella. Game art is not
redistributable, so nothing this makes is ever committed -- it is generated on the player's PC, into KSA's local mod
folder (Documents/My Games/Kitten Space Agency/mods/NcmKsa/{Meshes,Textures}), like the Deep sprites
(prototypes/ncm_openspace/sprites.py). The craft's XML (parts, masses, drives) is NCM's own and lives in the repository
(ncm/ksa/NcmKsa/content, .../vehicles).

Source: the game's own whole-car PROXY mesh of the Hella (one merged body + glass, baked textures) -- not the per-panel
meshes, which are posed by the vehicle entity's rig. Steps:
  1. WolvenKit.CLI uncook the proxy (if not already) into %LOCALAPPDATA%/NCM/ksa-bodies/raw.
  2. Re-axis it into KSA's craft frame: +X forward (KSA's thrust axis), +Y right, +Z down (roof towards -Z); centred.
  3. One mesh atlas node, `NcmHella_Body`; the glass is mapped to its own swatch in the texture.
  4. Textures (PNG): the baked body colour RECOLOURED to the Machine's paint (passport appearance.primary), an
     AO/roughness/metal map, a flat normal.

Usage: python tools/ksa-hella-body.py [--paint R,G,B] [--appearance archer_hella__basic_player_01] [--force]
"""
import argparse
import json
import os
import struct
import subprocess
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
WKIT = os.path.join(ROOT, "tools", "WolvenKit.Console-8.20.0", "WolvenKit.CLI.exe")
LOCAL = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "NCM", "ksa-bodies")
RAW = os.path.join(LOCAL, "raw")
MOD = os.path.join(os.path.expanduser("~"), "Documents", "My Games", "Kitten Space Agency", "mods", "NcmKsa")
DEEP_TEAL = (24, 78, 88)   # data.vehicle_config "Deep Teal" -- the owner's Hella
GLASS = (34, 42, 50)
LAMP = (222, 216, 196)


# ------------------------------------------------------------------------------------------------ glb in / out
def read_glb(path):
    data = open(path, "rb").read()
    _, _, length = struct.unpack("<III", data[:12])
    pos, js, binc = 12, None, b""
    while pos < length:
        clen, ctype = struct.unpack("<II", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        pos += 8 + clen
    return js, binc


COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    fmt, size = COMP[a["componentType"]]
    n = NCOMP[a["type"]]
    stride = bv.get("byteStride") or size * n
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = []
    for k in range(a["count"]):
        vals = struct.unpack_from("<" + fmt * n, binc, base + k * stride)
        if a.get("normalized") and fmt != "f":
            m = float((1 << (8 * size - (1 if fmt.islower() else 0))) - 1)
            vals = tuple(v / m for v in vals)
        out.append(vals if n > 1 else vals[0])
    return out


def write_glb(path, name, pos, nrm, uv, idx):
    """One node, one mesh, one primitive: POSITION, NORMAL, TEXCOORD_0, uint16 indices (as KSA's own meshes are)."""
    if len(pos) > 65535:
        raise ValueError("too many vertices for 16-bit indices: %d" % len(pos))
    b = bytearray()

    def view(blob, target):
        off = len(b)
        b.extend(blob)
        while len(b) % 4:
            b.append(0)
        return {"buffer": 0, "byteOffset": off, "byteLength": len(blob), "target": target}

    views = [view(b"".join(struct.pack("<3f", *p) for p in pos), 34962),
             view(b"".join(struct.pack("<3f", *p) for p in nrm), 34962),
             view(b"".join(struct.pack("<2f", *t) for t in uv), 34962),
             view(b"".join(struct.pack("<H", i) for i in idx), 34963)]
    mn = [min(p[k] for p in pos) for k in range(3)]
    mx = [max(p[k] for p in pos) for k in range(3)]
    js = {"asset": {"version": "2.0", "generator": "NCM ksa-hella-body.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"name": name, "mesh": 0}],
          "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "mode": 4}]}],
          "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": mn, "max": mx},
                        {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
                        {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
                        {"bufferView": 3, "componentType": 5123, "count": len(idx), "type": "SCALAR"}],
          "bufferViews": views, "buffers": [{"byteLength": len(b)}]}
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    while len(jb) % 4:
        jb += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(b)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(b), 0x004E4942) + bytes(b))
    return mn, mx


# ------------------------------------------------------------------------------------------------ the body
def to_ksa(v):
    """WolvenKit glTF (Y up, the car facing -Z, right = +X) -> KSA craft frame (+X forward, +Y right, +Z down)."""
    x, y, z = v
    return (-z, x, -y)


def uncook(appearance):
    if not os.path.exists(WKIT):
        sys.exit("WolvenKit.CLI not found at %s" % WKIT)
    os.makedirs(RAW, exist_ok=True)
    cmd = [WKIT, "uncook", os.path.join(GAME, "archive", "pc", "content"), "-o", RAW, "-gp", GAME,
           "-r", r"proxy\\%s\.mesh$" % appearance, "--mesh-export-type", "MeshOnly", "--mesh-export-lod-filter", "--uext", "png", "-v", "Minimal"]
    print("uncooking the %s proxy from your game files (a few minutes) ..." % appearance)
    subprocess.run(cmd, check=True)


def build(appearance, paint, force):
    src = os.path.join(RAW, "base", "vehicles", "appearances", "standard", "proxy", appearance)
    glb = os.path.join(src, appearance + ".glb")
    if not os.path.exists(glb) or force:
        uncook(appearance)
    if not os.path.exists(glb):
        sys.exit("no proxy mesh at %s" % glb)
    js, binc = read_glb(glb)
    mats = json.load(open(os.path.join(src, appearance + ".Material.json"), encoding="utf-8"))["Materials"]

    pos, nrm, uv, idx = [], [], [], []
    sub = -1
    for node in js["nodes"]:
        if "mesh" not in node:
            continue
        # a MeshOnly export drops material assignments; the proxy's submeshes follow its material list (Body, Glass, Lights)
        sub += 1
        mat = mats[sub]["Name"] if sub < len(mats) else "Body"
        swatch = (0.75, 0.25) if "glass" in mat.lower() else ((0.75, 0.75) if "light" in mat.lower() else None)
        for prim in js["meshes"][node["mesh"]]["primitives"]:
            P = accessor(js, binc, prim["attributes"]["POSITION"])
            N = accessor(js, binc, prim["attributes"]["NORMAL"]) if "NORMAL" in prim["attributes"] else [(0, 1, 0)] * len(P)
            T = accessor(js, binc, prim["attributes"]["TEXCOORD_0"]) if "TEXCOORD_0" in prim["attributes"] else [(0, 0)] * len(P)
            I = accessor(js, binc, prim["indices"])
            base = len(pos)
            pos += [to_ksa(p) for p in P]
            nrm += [to_ksa(n) for n in N]
            # the atlas: the baked body on the left half; glass (top) and lamp (bottom) swatches on the right
            uv += [swatch if swatch else (min(max(t[0], 0.0), 1.0) * 0.5, t[1]) for t in T]
            idx += [base + i for i in I]
            print("  %s: %d vertices, %d triangles (%s)" % (node.get("name"), len(P), len(I) // 3, mat))
    # centre the body on its bounding box (its centre of mass is set in the craft's XML)
    c = [(min(p[k] for p in pos) + max(p[k] for p in pos)) / 2 for k in range(3)]
    pos = [(p[0] - c[0], p[1] - c[1], p[2] - c[2]) for p in pos]

    os.makedirs(os.path.join(MOD, "Meshes"), exist_ok=True)
    os.makedirs(os.path.join(MOD, "Textures"), exist_ok=True)
    mn, mx = write_glb(os.path.join(MOD, "Meshes", "NcmHella_MeshAtlas.glb"), "NcmHella_Body", pos, nrm, uv, idx)
    print("  body %.2f m long, %.2f m wide, %.2f m tall (KSA frame)" % (mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]))

    # ---- textures: find the baked maps by their role in the material
    body = next(m for m in mats if m["Name"].lower() == "body")["Data"]

    def png(key):
        p = body.get(key)
        if not p:
            return None
        f = os.path.join(RAW, p.replace("\\", os.sep)).replace(".xbm", ".png")
        return Image.open(f) if os.path.exists(f) else None

    diffuse = png("BaseColor").convert("RGB")
    W, H = diffuse.size
    out = Image.new("RGB", (W * 2, H), GLASS)
    out.paste(LAMP, (W, H // 2, W * 2, H))
    px = diffuse.load()
    o = out.load()
    pr, pg, pb = paint
    ref = 0.22   # the baked paint's own brightness (dark grey on the player car)
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            mx_, mn_ = max(r, g, b), min(r, g, b)
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            sat = (mx_ - mn_) / mx_ if mx_ else 0
            if sat < 0.18 and 0.10 < lum < 0.55:   # the painted body, not tyres, chrome, lights or the gold stripe
                k = min(lum / ref, 2.2)
                w = 0.85
                r = int(r * (1 - w) + min(255, pr * k) * w)
                g = int(g * (1 - w) + min(255, pg * k) * w)
                b = int(b * (1 - w) + min(255, pb * k) * w)
            o[x, y] = (r, g, b)
    out.save(os.path.join(MOD, "Textures", "NcmHella_Diffuse.png"))

    rough, metal = png("Roughness"), png("Metalness")
    orm = Image.new("RGB", (W * 2, H), (255, 26, 0))   # glass: smooth, not metal
    rl = rough.convert("L").resize((W, H)) if rough else Image.new("L", (W, H), 140)
    ml = metal.convert("L").resize((W, H)) if metal else Image.new("L", (W, H), 0)
    orm.paste(Image.merge("RGB", (Image.new("L", (W, H), 255), rl, ml)), (0, 0))
    orm.save(os.path.join(MOD, "Textures", "NcmHella_PBR.png"))
    Image.new("RGB", (4, 4), (128, 128, 255)).save(os.path.join(MOD, "Textures", "NcmHella_Normal.png"))
    print("  textures: paint %s, %dx%d" % (",".join(map(str, paint)), W * 2, H))
    json.dump({"appearance": appearance, "paint": list(paint), "lengthM": mx[0] - mn[0], "widthM": mx[1] - mn[1], "heightM": mx[2] - mn[2]},
              open(os.path.join(MOD, "NcmHella_body.json"), "w", encoding="utf-8"))
    print("KSA Hella body written to %s (local only: CD PROJEKT art, never committed)" % MOD)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--paint", default=",".join(map(str, DEEP_TEAL)))
    ap.add_argument("--appearance", default="archer_hella__basic_player_01")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    build(a.appearance, tuple(int(v) for v in a.paint.split(",")), a.force)
