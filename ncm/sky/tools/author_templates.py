"""NCM Sky: author the body templates (.ent JSON) from the game's own q201 Earth template.

The game's `q201_q203_earth_globe.ent` is the whole q201 scene (globe, atmosphere, city lights, two debug lights, a
seat) under a plain `entEntity` root, which the game's TeleportationFacility cannot move. Each template here keeps
that file's structure, makes the root a `gameObject` (so redscript can turn it on every axis), keeps only the mesh
components a body needs, and sets their meshes, appearances and absolute sizes.

The bodies of the NCWE space render (L358) use meshes NCWE cooked into the world layer (`ncm_world_layer`, project
`ncm/ncwe/ncm_world_layer.ncwe`): every custom mesh is 2 m across (radius 1 m), appearance `default`.

  python ncm/sky/tools/author_templates.py <q201 json from WolvenKit `convert serialize`> <out dir>

Writes one JSON per body; `tools/build-sky.ps1` turns them into .ent with WolvenKit `convert deserialize`.
"""
import copy
import io
import json
import os
import sys

Q201_R = 0.49            # the q201 globe mesh is ~0.98 m across
HIDE_M = 30000.0         # autoHideDistance: never hidden inside REDengine's 16 km box
Q201_GLOBE = "base\\environment\\decoration\\unique\\quest\\q201_q203\\q201_q203_earth_globe.mesh"
DOME = "ncwe\\custom\\wl_dome_a313d3\\wl_dome_a313d3.mesh"
EARTH = "ncwe\\custom\\wl_body_e_33d782\\wl_body_e_33d782.mesh"
MOON = "ncwe\\custom\\wl_body_m_2477ca\\wl_body_m_2477ca.mesh"

# body -> (globe mesh, its radius in mesh units, appearance, radius m, atmosphere ratio or None, casts shadows)
BODIES = {
    "earth_1km": (Q201_GLOBE, Q201_R, "q201_earth", 1000.0, 1.02, True),     # SKY-1, kind 1
    "dome": (DOME, 1.0, "default", 2500.0, None, False),                     # kind 2 (half-size 2,500 m)
    "earth_r1000": (EARTH, 1.0, "default", 1000.0, 1.015, False),            # kinds 3-6
    "earth_r100": (EARTH, 1.0, "default", 100.0, 1.015, False),
    "earth_r10": (EARTH, 1.0, "default", 10.0, 1.015, False),
    "earth_r1": (EARTH, 1.0, "default", 1.0, 1.015, False),
    "moon_r100": (MOON, 1.0, "default", 100.0, None, False),                 # kinds 7-9
    "moon_r10": (MOON, 1.0, "default", 10.0, None, False),
    "moon_r1": (MOON, 1.0, "default", 1.0, None, False),
}


def cname(c):
    n = c.get("name")
    return n.get("$value") if isinstance(n, dict) else n


def set_cname(obj, key, value):
    v = obj.get(key)
    if isinstance(v, dict) and "$value" in v:
        v["$value"] = value
    else:
        obj[key] = {"$type": "CName", "$storage": "string", "$value": value}


def set_mesh(c, path):
    ref = c["mesh"]
    dp = ref.get("DepotPath")
    if isinstance(dp, dict):
        dp["$storage"] = "string"
        dp["$value"] = path
    else:
        ref["DepotPath"] = {"$type": "ResourcePath", "$storage": "string", "$value": path}


def author(src, mesh, meshR, appearance, radius, air, shadows):
    d = copy.deepcopy(src)
    root = d["Data"]["RootChunk"]

    def fix(chunks):
        out = []
        for c in chunks:
            t = c.get("$type")
            if t in ("entEntity", "gameObject"):
                c["$type"] = "gameObject"
                out.append(c)
                continue
            if t != "entMeshComponent":
                continue
            name = cname(c)
            if name == "Globe":
                set_mesh(c, mesh)
                set_cname(c, "meshAppearance", appearance)
                s = radius / meshR
            elif name == "Atmoshpere" and air:
                s = radius * air / Q201_R          # the q201 atmosphere shell, around whichever globe
            else:
                continue
            c["visualScale"] = {"$type": "Vector3", "X": s, "Y": s, "Z": s}
            c["autoHideDistance"] = HIDE_M
            if not shadows:
                for k in ("castShadows", "castLocalShadows", "castRayTracedGlobalShadows", "castRayTracedLocalShadows"):
                    if k in c:
                        c[k] = "Never"
            out.append(c)
        return out

    cd = root["compiledData"]["Data"]
    new_chunks, cruid = [], {}
    for i, c in enumerate(cd["Chunks"]):
        kept = fix([c])
        if kept:
            cruid[str(len(new_chunks))] = cd["CruidDict"].get(str(i), "0")
            new_chunks.append(kept[0])
    cd["Chunks"] = new_chunks
    cd["CruidDict"] = cruid
    root["components"] = fix(root["components"])
    root["entity"]["Data"]["$type"] = "gameObject"
    return d


def main():
    src_path, out_dir = sys.argv[1], sys.argv[2]
    with io.open(src_path, encoding="utf-8") as f:
        src = json.load(f)
    os.makedirs(out_dir, exist_ok=True)
    for body, (mesh, meshR, app, radius, air, shadows) in BODIES.items():
        d = author(src, mesh, meshR, app, radius, air, shadows)
        with io.open(os.path.join(out_dir, body + ".ent.json"), "w", encoding="utf-8", newline="") as f:
            json.dump(d, f, indent=1)
        kept = [cname(c) or c["$type"] for c in d["Data"]["RootChunk"]["compiledData"]["Data"]["Chunks"]]
        print(body, "r=%g m" % radius, kept)


if __name__ == "__main__":
    main()
