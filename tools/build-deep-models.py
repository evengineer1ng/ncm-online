"""Build the WebGL Deep view's vehicle models (owner, 2026-10-13: "make sure vehicles use their appropriate png in webgl
deep? everyone is a hella" -> "extract them its still a cyberpunk mod").

For every vehicle in NCM's catalogue (ncm/core/data/vehicle_catalogue.lua KEY), the game's body shell mesh
(<model>__ext01_body_01.mesh; a variant uses its base model) is unbundled and exported with WolvenKit 8.20, and its
LOWEST-detail LOD is kept (a car in Deep is a few hundred pixels at most). Written to
ncm/online/resources/ncm_world/web/deep/models/:
    <model>.js     NCM_DEEP_MODEL("<model>", { s: [scale], p: int16 xyz (base64), n: int8 xyz, i: uint16 })
                   positions in GAME axes (x right, y forward, z up), metres = p * s
    index.js       NCM_DEEP_MODELS = { "<vehicleKey>": "<model>", ... }
A page cannot fetch from a bundled resource (KB-210), but it can load a <script>: so models are scripts.

Usage: python tools/build-deep-models.py
"""
import base64
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WK = os.path.join(ROOT, "tools", "WolvenKit.Console-8.20.0", "WolvenKit.CLI.exe")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
OUT = os.path.join(ROOT, "ncm", "online", "resources", "ncm_world", "web", "deep", "models")
CATALOGUE = os.path.join(ROOT, "ncm", "core", "data", "vehicle_catalogue.lua")

# a record base whose own body mesh does not exist -> the model that carries its shape
VARIANT = {
    "ncm_atlus_av": "av_zetatech_atlus",
    "v_sport2_porsche_911turbo_cabrio": "v_sport2_porsche_911turbo",
    "v_sport2_quadra_type66_avenger": "v_sport2_quadra_type66",
    "v_sport2_villefort_deleon_sport": "v_sport2_villefort_deleon",
    "v_sportbike1_yaiba_kusanagi_animal": "v_sportbike1_yaiba_kusanagi",
    "v_sportbike1_yaiba_kusanagi_tyger": "v_sportbike1_yaiba_kusanagi",
}
# models whose shell is not named <model>__ext01_body_01.mesh
MESH_NAME = {
    "v_sportbike2_arch": "v_sportbike2_arch_nemesis__ext01_body_b_01.mesh",
    "v_sportbike3_brennan_apollo": "v_sportbike3_brennan_apollo__ext01_body_b_01.mesh",
    "v_sportbike3_brennan_apollo_nomad": "v_sportbike3_brennan_apollo__ext01_body_b_01.mesh",
    "v_sportbike3_brennan_apollo_sport": "v_sportbike3_brennan_apollo__ext01_body_b_01.mesh",
}


def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def catalogue():
    text = open(CATALOGUE, encoding="utf-8").read()
    keys = {}
    for base, key in re.findall(r'Vehicle_([a-z0-9_]+)\s*=\s*"([a-z0-9_]+)"', text):
        keys[base] = key
    return keys


def lowest_lod(glb):
    b = open(glb, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    bin_off = 20 + jl + 8
    lods = {}
    for m in j["meshes"]:
        mm = re.search(r"LOD_(\d+)$", m.get("name", ""))
        lods.setdefault(int(mm.group(1)) if mm else 0, []).append(m)
    lod = max(lods)

    def acc(i):
        a = j["accessors"][i]
        v = j["bufferViews"][a["bufferView"]]
        off = bin_off + v.get("byteOffset", 0) + a.get("byteOffset", 0)
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "VEC2": 2}[a["type"]]
        fmt = {5126: "f", 5123: "H", 5125: "I", 5121: "B", 5122: "h"}[a["componentType"]]
        size = struct.calcsize(fmt)
        stride = v.get("byteStride", n * size)
        out = []
        for k in range(a["count"]):
            out.append(struct.unpack_from("<" + fmt * n, b, off + k * stride))
        return out

    pos, nor, idx = [], [], []
    for m in lods[lod]:
        for pr in m["primitives"]:
            base = len(pos)
            P = acc(pr["attributes"]["POSITION"])
            N = acc(pr["attributes"]["NORMAL"]) if "NORMAL" in pr["attributes"] else [(0, 1, 0)] * len(P)
            # glTF (WolvenKit): x right, y up, z = -forward  ->  game: x right, y forward, z up
            pos += [(p[0], -p[2], p[1]) for p in P]
            nor += [(n[0], -n[2], n[1]) for n in N]
            idx += [base + t[0] for t in acc(pr["indices"])]
    return lod, pos, nor, idx


def pack(pos, nor, idx):
    if len(pos) > 65535:
        raise ValueError("too many vertices for uint16 indices: %d" % len(pos))
    ext = max(max(abs(c) for c in p) for p in pos) or 1.0
    s = ext / 32767.0
    P = b"".join(struct.pack("<hhh", *(int(round(c / s)) for c in p)) for p in pos)
    N = b"".join(struct.pack("<bbb", *(max(-127, min(127, int(round(c * 127)))) for c in n)) for n in nor)
    I = struct.pack("<%dH" % len(idx), *idx)
    return {"s": s, "p": base64.b64encode(P).decode(), "n": base64.b64encode(N).decode(), "i": base64.b64encode(I).decode(),
            "v": len(pos), "t": len(idx) // 3}


def main():
    keys = catalogue()
    want = {}   # model -> mesh filename
    model_of = {}   # vehicleKey -> model
    for base, key in sorted(keys.items()):
        model = VARIANT.get(base, base)
        mesh = MESH_NAME.get(base, MESH_NAME.get(model, model + "__ext01_body_01.mesh"))
        want[model] = mesh
        model_of[key] = model
    work = tempfile.mkdtemp(prefix="deep-models-")
    regex = "(" + "|".join(re.escape(m) for m in sorted(set(want.values()))) + ")$"
    for sub in ("content", "ep1"):
        run([WK, "unbundle", os.path.join(GAME, "archive", "pc", sub), "-o", os.path.join(work, sub), "--regex", regex])
    found = {}
    for base_dir, _, files in os.walk(work):
        for f in files:
            if f.endswith(".mesh") and "\\decoration\\" not in base_dir and "/decoration/" not in base_dir.replace("\\", "/") + "/":
                found.setdefault(f, os.path.join(base_dir, f))
    os.makedirs(OUT, exist_ok=True)
    built, missing = {}, []
    for model, mesh in sorted(want.items()):
        src = found.get(mesh)
        if not src:
            missing.append(model)
            continue
        ex = os.path.join(work, "glb", model)
        os.makedirs(ex, exist_ok=True)
        code, log = run([WK, "export", src, "--outpath", ex, "--gamepath", GAME])
        glbs = [os.path.join(ex, f) for f in os.listdir(ex) if f.endswith(".glb")]
        if not glbs:
            missing.append(model)
            print("export failed", model, log[-300:])
            continue
        lod, pos, nor, idx = lowest_lod(glbs[0])
        data = pack(pos, nor, idx)
        with open(os.path.join(OUT, model + ".js"), "w", encoding="utf-8", newline="\n") as f:
            f.write("// %s (LOD %d, %d triangles), from the game's %s -- tools/build-deep-models.py\n" % (model, lod, data["t"], mesh))
            f.write("NCM_DEEP_MODEL(%s, %s);\n" % (json.dumps(model), json.dumps(data)))
        built[model] = data["t"]
        print("%-40s LOD %d %6d tris %7d bytes" % (model, lod, data["t"], os.path.getsize(os.path.join(OUT, model + ".js"))))
    index = {k: m for k, m in model_of.items() if m in built}
    with open(os.path.join(OUT, "index.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("// vehicleKey -> model file (tools/build-deep-models.py); a key not here draws the sprite\n")
        f.write("var NCM_DEEP_MODELS = %s;\n" % json.dumps(index, indent=1, sort_keys=True))
    shutil.rmtree(work, ignore_errors=True)
    print("built %d models for %d vehicle keys; missing: %s" % (len(built), len(index), ", ".join(missing) or "none"))


if __name__ == "__main__":
    sys.exit(main())
