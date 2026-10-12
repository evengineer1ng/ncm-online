"""NCM Build starter kit (2026-10-12, owner: "i cant see any evidence of build at all anywhere"): the physical pieces
players attach to Machines (and later to each other), as OBJ + MTL for NCWE Studio to import and cook.

Frame (= the Machine frame and NCWE's Z-up import): x right, y forward, z up, metres. Every piece's ORIGIN is its
attachment point (where it meets its parent), so an attachment's stored transform is exactly where it is glued.

    python -I tools/deep/ncwe/build-build-kit.py <out_dir>

Each piece: <id>.obj + <id>.mtl. Sizes, masses and areas live in core `build.attach` (one source of physics)."""
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser("~"), "ncwe-work", "kit")

MATS = {   # name -> (Kd r g b, Ks, Ns)
    "steel": ((0.55, 0.57, 0.6), 0.6, 60),
    "carbon": ((0.07, 0.07, 0.08), 0.4, 40),
    "paint": ((0.85, 0.35, 0.08), 0.3, 30),
    "rubber": ((0.04, 0.04, 0.04), 0.05, 5),
    "nozzle": ((0.32, 0.27, 0.22), 0.5, 50),
    "glass": ((0.15, 0.55, 0.65), 0.8, 90),
    "panel": ((0.7, 0.7, 0.68), 0.2, 20),
}


class Mesh:
    def __init__(self):
        self.v, self.f = [], []   # f: (material, [indices 1-based])

    def add(self, verts, faces, mat):
        base = len(self.v)
        self.v.extend(verts)
        for face in faces:
            self.f.append((mat, [base + i + 1 for i in face]))

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.add(v, f, mat)

    def revolve(self, profile, axis, mat, seg=24, caps=True):
        """profile: [(along, radius)], revolved about `axis` ("x", "y" or "z") through the origin."""
        v, f = [], []
        for a, r in profile:
            for s in range(seg):
                t = 2 * math.pi * s / seg
                c, d = r * math.cos(t), r * math.sin(t)
                v.append({"x": (a, c, d), "y": (c, a, d), "z": (c, d, a)}[axis])
        n = len(profile)
        for i in range(n - 1):
            for s in range(seg):
                a0, a1 = i * seg + s, i * seg + (s + 1) % seg
                b0, b1 = (i + 1) * seg + s, (i + 1) * seg + (s + 1) % seg
                f.append((a0, a1, b1, b0))
        if caps:
            for ring, flip in ((0, True), (n - 1, False)):
                if profile[ring][1] > 1e-6:
                    idx = list(range(ring * seg, ring * seg + seg))
                    f.append(tuple(reversed(idx)) if flip else tuple(idx))
        self.add(v, f, mat)

    def wing(self, span, root, tip, thick, sweep, mat, axis="x"):
        """An extruded airfoil along +x (span), chord along y (leading edge at +y), thickness along z."""
        prof = []
        for i in range(12):
            t = i / 11
            y = 1 - t
            zt = 5 * thick * (0.2969 * math.sqrt(max(y, 0)) - 0.126 * y - 0.3516 * y ** 2 + 0.2843 * y ** 3 - 0.1015 * y ** 4)
            prof.append((y, zt))
        loop = [(y, z) for y, z in prof] + [(y, -z) for y, z in reversed(prof[1:-1])]
        v, f = [], []
        for k, (xs, chord, off) in enumerate(((0.0, root, 0.0), (span, tip, -sweep))):
            for y, z in loop:
                v.append((xs, (y - 0.5) * chord + off, z * chord))
        m = len(loop)
        for i in range(m):
            f.append((i, (i + 1) % m, m + (i + 1) % m, m + i))
        f.append(tuple(range(m - 1, -1, -1)))
        f.append(tuple(range(m, 2 * m)))
        self.add(v, f, mat)

    def write(self, name):
        os.makedirs(OUT, exist_ok=True)
        with open(os.path.join(OUT, name + ".mtl"), "w", newline="\n") as m:
            for k, (kd, ks, ns) in MATS.items():
                m.write("newmtl %s\nKd %.3f %.3f %.3f\nKs %.2f %.2f %.2f\nNs %d\n\n" % (k, kd[0], kd[1], kd[2], ks, ks, ks, ns))
        with open(os.path.join(OUT, name + ".obj"), "w", newline="\n") as o:
            o.write("# NCM Build kit: %s (origin = attachment point; x right, y forward, z up)\nmtllib %s.mtl\no %s\n" % (name, name, name))
            for x, y, z in self.v:
                o.write("v %.4f %.4f %.4f\n" % (x, y, z))
            cur = None
            for mat, idx in self.f:
                if mat != cur:
                    o.write("usemtl %s\n" % mat)
                    cur = mat
                o.write("f %s\n" % " ".join(str(i) for i in idx))
        print("%-14s %5d verts %5d faces" % (name, len(self.v), len(self.f)))


def piece(name, build):
    m = Mesh()
    build(m)
    m.write(name)


PIECES = {
    # structure (origin at one end; the member runs up +z)
    "kit_strut": lambda m: (m.revolve([(0, 0.035), (1.0, 0.035)], "z", "steel", 12), m.box(-0.06, 0.06, -0.06, 0.06, 0, 0.02, "steel")),
    "kit_beam": lambda m: m.box(-0.04, 0.04, -0.04, 0.04, 0, 1.0, "steel"),
    "kit_panel_s": lambda m: m.box(-0.25, 0.25, -0.25, 0.25, 0, 0.02, "panel"),
    "kit_panel_m": lambda m: m.box(-0.5, 0.5, -0.5, 0.5, 0, 0.02, "panel"),
    "kit_panel_l": lambda m: m.box(-1.0, 1.0, -1.0, 1.0, 0, 0.025, "panel"),
    "kit_wall": lambda m: m.box(-1.0, 1.0, -0.04, 0.04, 0, 2.5, "panel"),
    # aero (origin at the mount on the underside centre; span along x)
    "kit_wing_s": lambda m: m.wing(1.2, 0.32, 0.26, 0.12, 0.04, "carbon") or m.wing(-1.2, 0.32, 0.26, 0.12, 0.04, "carbon"),
    "kit_wing_l": lambda m: (m.wing(1.0, 0.48, 0.36, 0.12, 0.08, "carbon"), m.wing(-1.0, 0.48, 0.36, 0.12, 0.08, "carbon"),
                             m.box(-1.02, -0.98, -0.25, 0.25, -0.05, 0.25, "carbon"), m.box(0.98, 1.02, -0.25, 0.25, -0.05, 0.25, "carbon")),
    "kit_fin": lambda m: m.box(-0.015, 0.015, -0.2, 0.2, 0, 0.5, "carbon"),
    # running gear (origin at the axle; wheel turns about x)
    "kit_wheel_pod": lambda m: (m.revolve([(-0.13, 0.25), (-0.13, 0.33), (0.13, 0.33), (0.13, 0.25)], "x", "rubber", 24),
                                m.revolve([(-0.11, 0.0), (-0.11, 0.25), (0.11, 0.25), (0.11, 0.0)], "x", "steel", 16)),
    # propulsion housings (origin at the mount; the nozzle opens toward -z, exhaust leaves along -z)
    "kit_nozzle_bell": lambda m: (m.revolve([(0.0, 0.12), (-0.12, 0.10), (-0.25, 0.14), (-0.45, 0.22), (-0.6, 0.27)], "z", "nozzle", 24, caps=False),
                                  m.box(-0.14, 0.14, -0.14, 0.14, 0, 0.06, "steel")),
    "kit_nozzle_ram": lambda m: (m.box(-0.3, 0.3, -0.3, 0.3, -0.05, 0, "steel"), m.revolve([(0, 0.12), (0.3, 0.12)], "z", "steel", 16)),
    "kit_nozzle_cold": lambda m: m.revolve([(0.0, 0.03), (-0.08, 0.025), (-0.15, 0.05)], "z", "nozzle", 12, caps=False),
    # stores and brains (origin at the mounting face)
    "kit_tank": lambda m: m.revolve([(0.0, 0.0), (0.05, 0.16), (0.15, 0.25), (0.85, 0.25), (0.95, 0.16), (1.0, 0.0)], "z", "paint", 20),
    "kit_controller": lambda m: (m.box(-0.15, 0.15, -0.1, 0.1, 0, 0.1, "carbon"), m.box(-0.12, 0.12, 0.101, 0.105, 0.02, 0.08, "glass")),
}

if __name__ == "__main__":
    for name, build in PIECES.items():
        piece(name, build)
