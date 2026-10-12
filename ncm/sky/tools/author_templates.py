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

# The ascent ring (2 km .. the 12 km seam): the Earth Underlay's holed Blue Marble annulus (`ncm_earth_underlay`, project
# `ncm/ncwe/ncm_earth_underlay.ncwe`), true size, origin at its pivot 6 km over the map. Each ring template is that mesh
# at a fixed scale k; redscript places it about the viewer (viewer + k * (pivot - viewer)), which draws exactly the true
# Earth beyond the map, only k times nearer -- inside the game's draw distance. Kinds 10-14 (NcmSky.reds RingScale).
UNDERLAY = "ncwe\\custom\\ncm_earth_underlay_5a1366\\ncm_earth_underlay_5a1366.mesh"
RING_K = (0.04, 0.028, 0.02, 0.014, 0.01)
for _k in RING_K:
    BODIES["ring_k%03d" % round(_k * 1000)] = (UNDERLAY, 1.0, "default", _k, None, False)

# The Build kit (kinds 15-29, core build.attach KIT_ORDER; NCWE project ncm/ncwe/ncm_build_kit.ncwe -> required mod
# ncm_build_kit-assets): true size, origin at the attachment point, identity orientation. Cast shadows: they are parts
# of a car, not of the sky.
KIT = ["kit_strut_d6cac0", "kit_beam_9efd40", "kit_panel_s_97233f", "kit_panel_m_a01c30", "kit_panel_l_01f755",
       "kit_wall_2f4248", "kit_wing_s_74c011", "kit_wing_l_a6dd30", "kit_fin_0c3cb5", "kit_wheel_pod_eb5105",
       "kit_nozzle_bell_9ac09b", "kit_nozzle_ram_8f53d1", "kit_nozzle_cold_e6a403", "kit_tank_e63cbb", "kit_controller_1da79e"]
KIT_MESHES = set()
for _m in KIT:
    _path = "ncwe\\custom\\%s\\%s.mesh" % (_m, _m)
    KIT_MESHES.add(_path)
    BODIES[_m.rsplit("_", 1)[0]] = (_path, 1.0, "default", 1.0, None, True)


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
        if mesh != Q201_GLOBE:
            # KB-458 (2026-10-12, owner: "saw night city in the ocean a couple times"): the q201 Globe component is yawed
            # -41 deg in its entity. Every NCWE mesh's frame IS its body's own (the Earth: longitude 0 on +X, the pole on
            # +Z; the dome: J2000; the ring and kit: the game's x east, y north), so that yaw put Night City 41 deg of
            # longitude off (into the Pacific) and turned the star dome with it. Only the retired q201 proof keeps it.
            cd = d["Data"]["RootChunk"]["compiledData"]["Data"]["Chunks"]
            for c in d["Data"]["RootChunk"]["components"] + cd:
                lt = c.get("localTransform") if c.get("$type") == "entMeshComponent" else None
                if lt and lt.get("Orientation"):
                    lt["Orientation"].update({"i": 0, "j": 0, "k": 0, "r": 1})
        with io.open(os.path.join(out_dir, body + ".ent.json"), "w", encoding="utf-8", newline="") as f:
            json.dump(d, f, indent=1)
        kept = [cname(c) or c["$type"] for c in d["Data"]["RootChunk"]["compiledData"]["Data"]["Chunks"]]
        print(body, "r=%g m" % radius, kept)


if __name__ == "__main__":
    main()
