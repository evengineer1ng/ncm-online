"""NCM Sky assets (IDEA-1263 / L358): the celestial sphere as a six-face cube map in the J2000 equatorial frame.

Sources (licences checked 2026-10-10; none is redistributed by this script, which only reads them):
  * Milky Way: ESO/S. Brunier, eso0932a (CC BY 4.0) -- an equirectangular photograph of the whole sky in GALACTIC
    coordinates (l = 0 at the centre, increasing to the left). Reprojected here to equatorial.
  * Stars: the Yale Bright Star Catalogue, 5th ed. (public domain) -- the naked-eye stars drawn as sharp points on top,
    so the brightest stars stay crisp where the photograph blurs them.

Frame of the cube (what `space.deep` / NCM Sky orient): +X = RA 0h Dec 0, +Y = RA 6h Dec 0, +Z = the north celestial
pole. Faces px, nx, py, ny, pz, nz, each a gnomonic (cube) projection seen FROM THE CENTRE, so a pixel's colour is the
sky exactly in its direction -- no seam stretching.

  python tools/sky/build_sky_assets.py <sources dir> <out dir> [face size, default 2048]
"""
import gzip
import math
import os
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

# J2000 equatorial -> galactic rotation (Hipparcos, ESA 1997)
EQ_TO_GAL = np.array([
    [-0.0548755604, -0.8734370902, -0.4838350155],
    [+0.4941094279, -0.4448296300, +0.7469822445],
    [-0.8676661490, -0.1980763734, +0.4559837762],
])

# Each face: its outward axis, and the axes of increasing u (right) and v (down) as seen from inside.
FACES = {
    "px": (np.array([1, 0, 0]), np.array([0, -1, 0]), np.array([0, 0, -1])),
    "nx": (np.array([-1, 0, 0]), np.array([0, 1, 0]), np.array([0, 0, -1])),
    "py": (np.array([0, 1, 0]), np.array([1, 0, 0]), np.array([0, 0, -1])),
    "ny": (np.array([0, -1, 0]), np.array([-1, 0, 0]), np.array([0, 0, -1])),
    "pz": (np.array([0, 0, 1]), np.array([0, -1, 0]), np.array([1, 0, 0])),
    "nz": (np.array([0, 0, -1]), np.array([0, -1, 0]), np.array([-1, 0, 0])),
}


def face_dirs(face, n):
    axis, right, down = FACES[face]
    c = (np.arange(n) + 0.5) / n * 2 - 1
    u, v = np.meshgrid(c, c)
    d = axis[None, None, :] + u[..., None] * right[None, None, :] + v[..., None] * down[None, None, :]
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


def sample_milkyway(img, dirs):
    h, w, _ = img.shape
    g = dirs @ EQ_TO_GAL.T
    l = np.degrees(np.arctan2(g[..., 1], g[..., 0]))          # -180..180, 0 at the galactic centre
    b = np.degrees(np.arcsin(np.clip(g[..., 2], -1, 1)))
    x = (0.5 - l / 360.0) * w                                  # l increases to the LEFT in the panorama
    y = (0.5 - b / 180.0) * h
    x0 = np.floor(x).astype(int) % w
    y0 = np.clip(np.floor(y).astype(int), 0, h - 1)
    x1 = (x0 + 1) % w
    y1 = np.clip(y0 + 1, 0, h - 1)
    fx = (x - np.floor(x))[..., None]
    fy = (y - np.floor(y))[..., None]
    top = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    bot = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def read_bsc(path):
    """(ra rad, dec rad, vmag, B-V or None) for every star with a position (J2000)."""
    out = []
    with gzip.open(path, "rt", encoding="latin-1") as f:
        for line in f:
            if len(line) < 114 or not line[75:77].strip():
                continue
            try:
                ra = (int(line[75:77]) + int(line[77:79]) / 60 + float(line[79:83]) / 3600) * 15
                sign = -1 if line[83] == "-" else 1
                dec = sign * (int(line[84:86]) + int(line[86:88]) / 60 + int(line[88:90]) / 3600)
                vmag = float(line[102:107])
            except ValueError:
                continue
            try:
                bv = float(line[109:114])
            except ValueError:
                bv = None
            out.append((math.radians(ra), math.radians(dec), vmag, bv))
    return out


def star_colour(bv):
    """A rough B-V -> RGB (blue-white to orange)."""
    if bv is None:
        return np.array([1.0, 1.0, 1.0])
    t = max(-0.4, min(2.0, bv))
    r = 0.62 + 0.38 * min(1, (t + 0.4) / 1.0)
    g = 0.78 + 0.22 * (1 - abs(t - 0.4) / 1.6)
    b = 1.0 - 0.55 * max(0, (t - 0.0) / 2.0)
    return np.array([r, min(1, g), b])


def draw_stars(faces, stars, n):
    """Add each star as a small gaussian on whichever face it falls (brightness from magnitude)."""
    for ra, dec, vmag, bv in stars:
        if vmag > 6.0:
            continue
        d = np.array([math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec)])
        flux = 10 ** (-0.4 * (vmag - 1.0))                       # mag 1 -> 1.0
        amp = min(4.0, 0.55 * flux ** 0.5 + 0.12)
        sigma = 0.55 + 0.9 * min(1.0, flux ** 0.25)
        col = star_colour(bv) * amp
        for name, (axis, right, down) in FACES.items():
            k = d @ axis
            if k <= 0:
                continue
            p = d / k
            u, v = p @ right, p @ down
            if abs(u) > 1 or abs(v) > 1:
                continue
            px, py = (u + 1) / 2 * n - 0.5, (v + 1) / 2 * n - 0.5
            r = int(math.ceil(sigma * 3))
            x0, x1 = max(0, int(px) - r), min(n, int(px) + r + 2)
            y0, y1 = max(0, int(py) - r), min(n, int(py) + r + 2)
            if x0 >= x1 or y0 >= y1:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1]
            gsn = np.exp(-((xx - px) ** 2 + (yy - py) ** 2) / (2 * sigma * sigma))
            faces[name][y0:y1, x0:x1] += gsn[..., None] * col[None, None, :]


def main():
    src, out = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
    os.makedirs(out, exist_ok=True)
    mw = np.asarray(Image.open(os.path.join(src, "eso0932a.jpg")).convert("RGB"), dtype=np.float32) / 255.0
    mw = np.clip((mw - 0.015) * 0.85, 0, 1)                      # a darker sky: the photograph's own sky glow lifted out
    faces = {}
    for name in FACES:
        faces[name] = sample_milkyway(mw, face_dirs(name, n))
    stars = read_bsc(os.path.join(src, "bsc5.dat.gz"))
    draw_stars(faces, stars, n)
    for name, f in faces.items():
        img = Image.fromarray((np.clip(f, 0, 1) ** (1 / 1.1) * 255).astype(np.uint8))
        img.save(os.path.join(out, "sky_%s.png" % name))
    print("stars drawn: %d (to mag 6.0 of %d); faces %dx%d -> %s" % (sum(1 for s in stars if s[2] <= 6.0), len(stars), n, n, out))


if __name__ == "__main__":
    main()
