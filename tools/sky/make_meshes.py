"""NCM Sky meshes (IDEA-1263 / L358) as glTF 2.0, for NCWE `import_model` (up_axis Z).

  sky_cube.gltf   six inward-facing quads of a 2 m cube, one material per face (sky_px.png ... sky_nz.png from
                  build_sky_assets.py), in the J2000 frame: +X = RA 0h, +Y = RA 6h, +Z = the north celestial pole.
                  Each face is a gnomonic projection, so the texture is exact as seen from the centre.
  globe.gltf      a UV sphere of radius 1 m (equirectangular texture: u = longitude from -180 at the left, v = latitude
                  from +90 at the top), its axis +Z, longitude 0 on +X -- one mesh for Earth, Moon and planets, each
                  given its own texture in NCWE.

  python tools/sky/make_meshes.py <out dir> [sky faces dir]
"""
import base64
import json
import math
import os
import struct
import sys

FACES = {   # outward axis, right (u), down (v) -- the same table as build_sky_assets.py
    "px": ((1, 0, 0), (0, -1, 0), (0, 0, -1)),
    "nx": ((-1, 0, 0), (0, 1, 0), (0, 0, -1)),
    "py": ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
    "ny": ((0, -1, 0), (-1, 0, 0), (0, 0, -1)),
    "pz": ((0, 0, 1), (0, -1, 0), (1, 0, 0)),
    "nz": ((0, 0, -1), (0, -1, 0), (-1, 0, 0)),
}


def pack(fmt, rows):
    return b"".join(struct.pack(fmt, *r) for r in rows)


class Gltf:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accessors, self.meshes_prims = [], [], []
        self.materials, self.textures, self.images = [], [], []

    def add(self, data, target, comp, count, typ, mn=None, mx=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.views.append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data), "target": target})
        self.bin += data
        acc = {"bufferView": len(self.views) - 1, "componentType": comp, "count": count, "type": typ}
        if mn is not None:
            acc["min"], acc["max"] = mn, mx
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def material(self, name, image_uri, emissive):
        self.images.append({"uri": image_uri})
        self.textures.append({"source": len(self.images) - 1})
        t = {"index": len(self.textures) - 1}
        m = {"name": name, "doubleSided": True,
             "pbrMetallicRoughness": {"baseColorTexture": t, "metallicFactor": 0.0, "roughnessFactor": 1.0}}
        if emissive:
            m["emissiveTexture"] = t
            m["emissiveFactor"] = [1, 1, 1]
            m["pbrMetallicRoughness"]["baseColorFactor"] = [0, 0, 0, 1]
        self.materials.append(m)
        return len(self.materials) - 1

    def prim(self, pos, nrm, uv, idx, mat):
        p = self.add(pack("<3f", pos), 34962, 5126, len(pos), "VEC3",
                     [min(v[i] for v in pos) for i in range(3)], [max(v[i] for v in pos) for i in range(3)])
        n = self.add(pack("<3f", nrm), 34962, 5126, len(nrm), "VEC3")
        t = self.add(pack("<2f", uv), 34962, 5126, len(uv), "VEC2")
        i = self.add(pack("<I", [(x,) for x in idx]), 34963, 5125, len(idx), "SCALAR")
        self.meshes_prims.append({"attributes": {"POSITION": p, "NORMAL": n, "TEXCOORD_0": t}, "indices": i, "material": mat})

    def save(self, path, name):
        doc = {"asset": {"version": "2.0", "generator": "ncm tools/sky/make_meshes.py"},
               "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
               "meshes": [{"name": name, "primitives": self.meshes_prims}],
               "materials": self.materials, "textures": self.textures, "images": self.images,
               "samplers": [], "accessors": self.accessors, "bufferViews": self.views,
               "buffers": [{"byteLength": len(self.bin), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(self.bin)).decode()}]}
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f)


def sky_cube(out, faces_dir):
    g = Gltf()
    for name, (a, r, d) in FACES.items():
        mat = g.material("sky_" + name, "sky_%s.png" % name, True)
        pos, nrm, uv = [], [], []
        for (u, v) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            pos.append(tuple(a[i] + u * r[i] + v * d[i] for i in range(3)))
            nrm.append(tuple(-a[i] for i in range(3)))                   # facing the centre
            uv.append(((u + 1) / 2, (v + 1) / 2))
        # counter-clockwise as seen from the centre (screen y runs down with v)
        g.prim(pos, nrm, uv, [0, 2, 1, 0, 3, 2], mat)
    g.save(os.path.join(out, "sky_cube.gltf"), "ncm_sky_cube")


def globe(out, seg_lon=96, seg_lat=48):
    g = Gltf()
    mat = g.material("globe", "globe_placeholder.png", False)
    pos, nrm, uv, idx = [], [], [], []
    for j in range(seg_lat + 1):
        lat = math.pi / 2 - math.pi * j / seg_lat
        for i in range(seg_lon + 1):
            lon = -math.pi + 2 * math.pi * i / seg_lon
            n = (math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))
            pos.append(n)
            nrm.append(n)
            uv.append((i / seg_lon, j / seg_lat))
    w = seg_lon + 1
    for j in range(seg_lat):
        for i in range(seg_lon):
            a, b, c, d = j * w + i, j * w + i + 1, (j + 1) * w + i + 1, (j + 1) * w + i
            idx += [a, d, c, a, c, b]              # counter-clockwise seen from outside
    g.prim(pos, nrm, uv, idx, mat)
    g.save(os.path.join(out, "globe.gltf"), "ncm_globe")


def main():
    out = sys.argv[1]
    faces_dir = sys.argv[2] if len(sys.argv) > 2 else out
    os.makedirs(out, exist_ok=True)
    sky_cube(out, faces_dir)
    globe(out)
    print("wrote sky_cube.gltf and globe.gltf to", out)


if __name__ == "__main__":
    main()
