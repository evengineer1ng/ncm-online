"""Race Week Day 1 event art (IDEA-1261): banner textures + textured planes for NCWE import_model.

Every piece is a single-sided plane (OBJ + MTL + PNG), Z up, lying in the X-Z plane and facing +Y, pivot at the
bottom centre. NCWE's yaw turns +Y to (-sin yaw, cos yaw): the side that reads correctly faces that way.
Colours follow ncm_world/web/assets/banners/ncm-default.svg. Run without -I (Pillow lives in user site-packages).

    python tools/ncwe/race_week_art.py [out_dir]     (default ncm/ncwe/art)
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

BG = [(0x03, 0x12, 0x1d), (0x07, 0x33, 0x44), (0x3a, 0x06, 0x2d)]
CYAN, PINK, WHITE = (0x56, 0xed, 0xff), (0xff, 0x2f, 0x96), (0xf4, 0xfb, 0xff)
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight, 100])  # Bahnschrift: wght, wdth
    except Exception:
        pass
    return f


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for x in range(w):
        t = x / max(1, w - 1)
        a, b, u = (BG[0], BG[1], t / 0.56) if t < 0.56 else (BG[1], BG[2], (t - 0.56) / 0.44)
        c = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
        for y in range(h):
            px[x, y] = c
    return img


def checker(d, x0, y0, w, h, n_rows):
    s = h // n_rows
    for r in range(n_rows):
        for c in range(w // s):
            d.rectangle([x0 + c * s, y0 + r * s, x0 + (c + 1) * s - 1, y0 + (r + 1) * s - 1],
                        fill=WHITE if (r + c) % 2 == 0 else (0x05, 0x08, 0x0c))


def centred(d, cx, cy, text, f, fill):
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text((cx - (r - l) / 2 - l, cy - (b - t) / 2 - t), text, font=f, fill=fill)


def gantry(path):
    """15 m x 1.4 m START / FINISH banner for the footbridge fascia."""
    w, h = 4096, 384
    img = gradient(w, h)
    d = ImageDraw.Draw(img)
    checker(d, 0, 0, 384, h, 6)
    checker(d, w - 384, 0, 384, h, 6)
    d.rectangle([384, 0, w - 385, 10], fill=CYAN)
    d.rectangle([384, h - 11, w - 385, h - 1], fill=PINK)
    centred(d, w / 2, h * 0.40, "START  \u00b7  FINISH", font(190, 700), WHITE)
    centred(d, w / 2, h * 0.80, "NIGHT CITY MOTORSPORTS  \u00b7  RACE WEEK", font(64, 600), CYAN)
    img.save(path)
    return 15.0, 1.4


def pole(path, line1, line2):
    """1 m x 3.6 m vertical pole banner."""
    w, h = 512, 1843
    img = gradient(w, h).rotate(0)
    d = ImageDraw.Draw(img)
    checker(d, 0, 0, w, 128, 2)
    d.rectangle([0, h - 24, w, h], fill=PINK)
    d.rectangle([0, 128, w, 140], fill=CYAN)
    centred(d, w / 2, 330, "NCM", font(210, 800), WHITE)
    y = 560
    for word in line1.split():
        centred(d, w / 2, y, word, font(92, 700), CYAN)
        y += 112
    y += 60
    for word in line2.split():
        centred(d, w / 2, y, word, font(78, 600), WHITE)
        y += 96
    img.save(path)
    return 1.0, 3.6


def plane(obj_path, png_name, width, height):
    """A plane in X-Z facing +Y, pivot bottom centre, UV 0..1."""
    base = os.path.splitext(obj_path)[0]
    mtl = os.path.basename(base) + ".mtl"
    hw = width / 2
    with open(obj_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"mtllib {mtl}\no {os.path.basename(base)}\n")
        for x, z in ((-hw, 0), (hw, 0), (hw, height), (-hw, height)):
            f.write(f"v {x:.4f} 0 {z:.4f}\n")
        # seen from +Y, +X runs to the viewer's LEFT; so U runs 1 -> 0 along +X for the text to read correctly
        f.write("vt 1 0\nvt 0 0\nvt 0 1\nvt 1 1\nvn 0 1 0\nusemtl banner\n")
        f.write("f 1/1/1 4/4/1 3/3/1\nf 1/1/1 3/3/1 2/2/1\n")
    with open(base + ".mtl", "w", encoding="utf-8", newline="\n") as f:
        f.write(f"newmtl banner\nKd 1 1 1\nmap_Kd {png_name}\n")


def screen(path, title, sub, site):
    """8.4 m x 3.6 m (21:9) panel for the game's billboard_frame_m screens: the event takes over the city's ads."""
    w, h = 2048, 878
    img = gradient(w, h)
    d = ImageDraw.Draw(img)
    checker(d, 0, 0, w, 96, 2)
    d.rectangle([0, 96, w, 108], fill=CYAN)
    d.rectangle([0, h - 20, w, h], fill=PINK)
    centred(d, w / 2, 330, title, font(250, 800), WHITE)
    centred(d, w / 2, 560, sub, font(92, 650), CYAN)
    centred(d, w / 2, 720, site, font(64, 500), WHITE)
    img.save(path)
    return 8.4, 3.6


MARQUEE_L, MARQUEE_W, MARQUEE_H, MARQUEE_RIDGE = 9.0, 6.0, 3.0, 4.6


def marquee_atlas(path, brand, tag, colour):
    """2048 x 1024 atlas: top half the long wall (brand), bottom-left the gable end, bottom-right the roof canvas."""
    img = Image.new("RGB", (2048, 1024), WHITE)
    d = ImageDraw.Draw(img)
    wall = gradient(2048, 512)
    img.paste(wall, (0, 0))
    d.rectangle([0, 0, 2048, 40], fill=colour)
    d.rectangle([0, 472, 2048, 512], fill=colour)
    centred(d, 1024, 210, brand, font(230, 800), WHITE)
    centred(d, 1024, 380, tag, font(70, 600), CYAN)
    # gable end: white canvas, brand-colour band and NCM mark
    d.rectangle([0, 512, 1023, 1023], fill=(0xe8, 0xee, 0xf2))
    d.rectangle([0, 900, 1023, 1023], fill=colour)
    centred(d, 512, 600, "NCM", font(120, 800), (0x07, 0x33, 0x44))
    # roof: brand-colour and white stripes along the slope
    for i in range(8):
        d.rectangle([1024 + i * 128, 512, 1024 + i * 128 + 63, 1023], fill=colour)
    img.save(path)


def marquee_obj(obj_path, png_name):
    """A closed marquee: footprint L x W centred on the origin, walls H, ridge along X. Z up; pivot bottom centre."""
    L, W, H, R = MARQUEE_L / 2, MARQUEE_W / 2, MARQUEE_H, MARQUEE_RIDGE
    v, vt, f = [], [], []

    def quad(p, uv):  # p: 4 corners counter-clockwise seen from outside; uv: matching atlas coordinates
        base_v, base_t = len(v), len(vt)
        v.extend(p); vt.extend(uv)
        f.append([(base_v + i + 1, base_t + i + 1) for i in (0, 1, 2)])
        f.append([(base_v + i + 1, base_t + i + 1) for i in (0, 2, 3)])

    def tri(p, uv):
        base_v, base_t = len(v), len(vt)
        v.extend(p); vt.extend(uv)
        f.append([(base_v + i + 1, base_t + i + 1) for i in (0, 1, 2)])

    WALL = [(0, 0.5), (1, 0.5), (1, 1), (0, 1)]          # top half of the atlas (image rows 0-511)
    # long walls (-Y side seen from -Y reads left->right along +X; +Y side along -X)
    quad([(-L, -W, 0), (L, -W, 0), (L, -W, H), (-L, -W, H)], WALL)
    quad([(L, W, 0), (-L, W, 0), (-L, W, H), (L, W, H)], WALL)
    # gable ends (bottom-left quadrant), walls + triangle
    for s, ys in ((1, (-W, W)), (-1, (W, -W))):
        x = L * s
        quad([(x, ys[0], 0), (x, ys[1], 0), (x, ys[1], H), (x, ys[0], H)],
             [(0, 0), (0.5, 0), (0.5, 0.3), (0, 0.3)])
        tri([(x, ys[0], H), (x, ys[1], H), (x, 0, R)], [(0, 0.3), (0.5, 0.3), (0.25, 0.5)])
    # roof slopes (bottom-right quadrant: stripes run along the slope)
    ROOF = [(0.5, 0), (1, 0), (1, 0.5), (0.5, 0.5)]
    quad([(-L - 0.2, -W - 0.3, H - 0.1), (L + 0.2, -W - 0.3, H - 0.1), (L + 0.2, 0, R), (-L - 0.2, 0, R)], ROOF)
    quad([(L + 0.2, W + 0.3, H - 0.1), (-L - 0.2, W + 0.3, H - 0.1), (-L - 0.2, 0, R), (L + 0.2, 0, R)], ROOF)

    base = os.path.splitext(obj_path)[0]
    with open(obj_path, "w", encoding="utf-8", newline="\n") as fo:
        fo.write(f"mtllib {os.path.basename(base)}.mtl\no {os.path.basename(base)}\n")
        for x, y, z in v:
            fo.write(f"v {x:.4f} {y:.4f} {z:.4f}\n")
        for s, t in vt:
            fo.write(f"vt {s:.4f} {t:.4f}\n")
        fo.write("usemtl marquee\n")
        for tri_ in f:
            fo.write("f " + " ".join(f"{a}/{b}" for a, b in tri_) + "\n")
    with open(base + ".mtl", "w", encoding="utf-8", newline="\n") as fo:
        fo.write(f"newmtl marquee\nKd 1 1 1\nmap_Kd {png_name}\n")


MARQUEES = [("rw_marquee_quadra", "QUADRA", "HOSPITALITY · RACE WEEK", (0xff, 0x7a, 0x1a)),
            ("rw_marquee_mizutani", "MIZUTANI", "HOSPITALITY · RACE WEEK", (0xe0, 0x1e, 0x37)),
            ("rw_marquee_thorton", "THORTON", "HOSPITALITY · RACE WEEK", (0x2e, 0xb8, 0x5c)),
            ("rw_marquee_archer", "ARCHER", "HOSPITALITY · RACE WEEK", (0x3a, 0x7b, 0xff))]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join("ncm", "ncwe", "art")
    os.makedirs(out, exist_ok=True)
    for slug, brand, tag, colour in MARQUEES:
        marquee_atlas(os.path.join(out, slug + ".png"), brand, tag, colour)
        marquee_obj(os.path.join(out, slug + ".obj"), slug + ".png")
        print(slug, MARQUEE_L, MARQUEE_W, MARQUEE_RIDGE)
    main_flat(out)


def main_flat(out):
    pieces = [("rw_gantry_startfinish", lambda p: gantry(p)),
              ("rw_screen_startfinish", lambda p: screen(p, "START · FINISH", "NIGHT CITY MOTORSPORTS · RACE WEEK",
                                                         "PARQUE DEL MAR")),
              ("rw_screen_welcome", lambda p: screen(p, "RACE WEEK", "WELCOME, NIGHT CITY",
                                                     "STREETS OPEN · RACES EVERY 15 MINUTES"))]
    for slug, l1, l2 in (("rw_pole_welcome", "WELCOME TO RACE WEEK", "NIGHT CITY"),
                         ("rw_pole_pdm", "PARQUE DEL MAR", "START FINISH")):
        pieces.append((slug, lambda p, l1=l1, l2=l2: pole(p, l1, l2)))
    for slug, make in pieces:
        png = os.path.join(out, slug + ".png")
        w, h = make(png)
        plane(os.path.join(out, slug + ".obj"), slug + ".png", w, h)
        print(slug, w, h)


if __name__ == "__main__":
    main()
