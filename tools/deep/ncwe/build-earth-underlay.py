"""NCM Earth Underlay v2: a curved annulus of Earth under and around Night City.
Game frame (= NCM core space.deep): x east, y north, z up, metres; (0,0) = 35.37 N, 120.85 W; x/y are arc lengths.
The mesh's origin is its PIVOT, placed in NCWE at PIVOT below: high above the city, so every point a player reaches
over the map (ground to the 12 km Deep seam) is within NCWE's 10 km streaming distance of it."""
import math
from PIL import Image
R = 6371000.0
ORIGIN = (35.37, -120.85)
PIVOT = (0.0, -1750.0, 6000.0)          # map centre, 6 km up
CENTRE = (0.0, -1750.0)                 # the hole is centred on the map
R_IN, R_OUT = 9000.0, 420000.0          # hole under the playable map .. near the 12 km horizon (391 km)
Z0 = -5.0                               # just below sea level
RINGS, SEGS = 56, 192
TEX_HALF = 430000.0                     # texture covers +-430 km of game x/y
TEX_PX = 2048

def game_to_lla(x, y):
    lat = ORIGIN[0] + math.degrees(y / R)
    lon = ORIGIN[1] + math.degrees(x / (R * math.cos(math.radians(ORIGIN[0]))))
    return lat, lon

def surface_z(x, y):
    d2 = x * x + y * y                  # curvature about the geographic origin (where game z = height above sea)
    return Z0 - (R - math.sqrt(max(R * R - d2, 0.0)))

# ---- texture: resample the global Blue Marble into the game plane
src = Image.open(r'C:\Users\eveng\ncwe-inspect\tex\m00_d.dds').convert('RGB')
SW, SH = src.size
tex = Image.new('RGB', (TEX_PX, TEX_PX))
spx = src.load(); tpx = tex.load()
def sample(u, v):
    u %= SW; v = min(max(v, 0), SH - 1.001)
    x0, y0 = int(u), int(v); fx, fy = u - x0, v - y0; x1 = (x0 + 1) % SW; y1 = min(y0 + 1, SH - 1)
    c = [0, 0, 0]
    for (xx, yy, w) in ((x0, y0, (1-fx)*(1-fy)), (x1, y0, fx*(1-fy)), (x0, y1, (1-fx)*fy), (x1, y1, fx*fy)):
        p = spx[xx, yy]
        for k in range(3): c[k] += p[k] * w
    return tuple(int(v_) for v_ in c)
for j in range(TEX_PX):
    gy = CENTRE[1] + TEX_HALF - (j + 0.5) / TEX_PX * 2 * TEX_HALF
    for i in range(TEX_PX):
        gx = CENTRE[0] - TEX_HALF + (i + 0.5) / TEX_PX * 2 * TEX_HALF
        lat, lon = game_to_lla(gx, gy)
        tpx[i, j] = sample((lon + 180) / 360 * SW - 0.5, (90 - lat) / 180 * SH - 0.5)
tex.save('ncm_earth_underlay_d.png')

# ---- mesh: rings spaced geometrically (dense near the city, sparse at the horizon)
verts, uvs, norms, faces = [], [], [], []
for r_i in range(RINGS + 1):
    rad = R_IN * (R_OUT / R_IN) ** (r_i / RINGS)
    for s in range(SEGS):
        a = 2 * math.pi * s / SEGS
        gx, gy = CENTRE[0] + rad * math.cos(a), CENTRE[1] + rad * math.sin(a)
        gz = surface_z(gx, gy)
        verts.append((gx - PIVOT[0], gy - PIVOT[1], gz - PIVOT[2]))
        uvs.append(((gx - (CENTRE[0] - TEX_HALF)) / (2 * TEX_HALF), (gy - (CENTRE[1] - TEX_HALF)) / (2 * TEX_HALF)))
        nx, ny, nz = gx / R, gy / R, 1.0          # outward Earth normal, near-vertical
        l = math.sqrt(nx * nx + ny * ny + nz * nz); norms.append((nx / l, ny / l, nz / l))
for r_i in range(RINGS):
    for s in range(SEGS):
        a = r_i * SEGS + s; b = r_i * SEGS + (s + 1) % SEGS
        c = (r_i + 1) * SEGS + (s + 1) % SEGS; d = (r_i + 1) * SEGS + s
        faces.append((a, b, c)); faces.append((a, c, d))   # counter-clockwise seen from above (+z)
# v2 (2026-10-12): NCWE exports the streaming box as the mesh's WORLD BOUNDS +- the streaming distance (max 10 km), not
# the pivot +- 10 km: v1's box topped out at z ~ +9.99 km, so the Earth unloaded 2 km below the 12 km Deep seam (a black
# void while climbing). A 1 cm marker triangle at the pivot (6 km up, invisible) lifts the bounds: the box now reaches ~16 km.
m0 = len(verts)
for (dx, dy) in ((0.0, 0.0), (0.01, 0.0), (0.0, 0.01)):
    verts.append((dx, dy, 0.0)); uvs.append((0.5, 0.5)); norms.append((0.0, 0.0, 1.0))
faces.append((m0, m0 + 1, m0 + 2))
with open('ncm_earth_underlay.mtl', 'w') as f:
    f.write('newmtl earth\nKd 1 1 1\nKa 0 0 0\nKs 0 0 0\nNs 1\nmap_Kd ncm_earth_underlay_d.png\n')
with open('ncm_earth_underlay.obj', 'w') as f:
    f.write('# NCM Earth Underlay v2 -- origin = pivot at game (%.0f, %.0f, %.0f), z up\nmtllib ncm_earth_underlay.mtl\no ncm_earth_underlay\n' % PIVOT)
    for v in verts: f.write('v %.3f %.3f %.3f\n' % v)
    for t in uvs: f.write('vt %.6f %.6f\n' % t)
    for n in norms: f.write('vn %.5f %.5f %.5f\n' % n)
    f.write('usemtl earth\ns 1\n')
    for (a, b, c) in faces: f.write('f %d/%d/%d %d/%d/%d %d/%d/%d\n' % (a+1, a+1, a+1, b+1, b+1, b+1, c+1, c+1, c+1))
zs = [surface_z(CENTRE[0] + rr, CENTRE[1]) for rr in (R_IN, 50000, 200000, R_OUT)]
print('verts', len(verts), 'tris', len(faces), 'surface z at 9/50/200/420 km:', [round(z) for z in zs])
