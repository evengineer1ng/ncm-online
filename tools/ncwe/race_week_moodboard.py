"""Cut the owner's Race Week moodboard (2026-10-08) into sign textures for the city-wide takeover (IDEA-1268).

    python race_week_moodboard.py <moodboard.png> [--sheet out.png]

Each panel becomes ncm/ncwe/art/city/rw_city_<name>.png, upscaled (Lanczos) to a texture width and lightly sharpened,
plus a matching .obj plane (race_week_art.plane: pivot at bottom centre, facing +Y). `KIND` decides where a sign may go:
  wide   -- billboards and building screens (aspect > 1.6)
  poster -- portrait billboards / wall posters
  square -- transit / small screens
  pole   -- vertical pole banners (street lamps)
"""
import argparse, os, sys
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import race_week_art as art

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "ncm", "ncwe", "art", "city")

# (name, kind, box) in moodboard pixels (1536 x 1024); boxes inset a few px from the gutters
PANELS = [
    ("hero", "wide", (362, 52, 868, 214)),
    ("drivers", "poster", (1172, 6, 1346, 282)),
    ("ncm_poster", "poster", (1366, 16, 1530, 282)),
    ("quadra", "wide", (8, 292, 422, 438)),
    ("nodes", "wide", (432, 292, 811, 438)),
    ("streets", "wide", (820, 292, 1185, 438)),
    ("mizutani", "wide", (1195, 292, 1527, 438)),
    ("kusanagi", "wide", (9, 449, 428, 593)),
    ("orbital", "wide", (439, 449, 808, 593)),
    ("arasaka", "wide", (819, 449, 1202, 593)),
    ("samurai", "wide", (1213, 449, 1527, 593)),
    ("welcome", "wide", (9, 603, 401, 736)),
    ("nihongo", "wide", (414, 603, 783, 736)),
    ("helmet", "wide", (795, 603, 1137, 736)),
    ("all_eyes", "wide", (1149, 603, 1526, 736)),
    ("badlands", "wide", (10, 745, 434, 868)),
    ("obsession", "wide", (445, 745, 787, 868)),
    ("skyline", "wide", (798, 745, 1527, 868)),
    ("pole_ncm", "pole", (28, 902, 68, 1002)),
    ("pole_kanji", "pole", (103, 902, 144, 1002)),
    ("pole_check", "pole", (184, 902, 227, 1002)),
    ("pole_palm", "pole", (263, 902, 306, 1002)),
    ("pole_oni", "pole", (339, 902, 382, 1002)),
    ("pole_nodes", "pole", (414, 902, 457, 1002)),
    ("pole_yellow", "pole", (488, 902, 531, 1002)),
    ("pole_rider", "pole", (563, 902, 606, 1002)),
    ("sq_car", "square", (990, 890, 1098, 1005)),
    ("sq_moves", "square", (1124, 890, 1241, 1005)),
    ("sq_rider", "square", (1267, 890, 1383, 1005)),
    ("sq_nodes", "square", (1407, 890, 1525, 1005)),
]
TEX_W = {"wide": 2048, "poster": 1024, "square": 1024, "pole": 512}
# physical base size of the plane (metres, width) -- placements scale it to the frame they cover
BASE_W = {"wide": 8.4, "poster": 3.0, "square": 2.0, "pole": 1.0}


def cut(src, name, kind, box):
    im = src.crop(box)
    w = TEX_W[kind]
    h = max(1, round(w * im.height / im.width))
    im = im.resize((w, h), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    png = os.path.join(OUT, f"rw_city_{name}.png")
    im.save(png, optimize=True)
    bw = BASE_W[kind]
    bh = round(bw * im.height / im.width, 4)
    art.plane(os.path.join(OUT, f"rw_city_{name}.obj"), f"rw_city_{name}.png", bw, bh)
    return {"name": name, "kind": kind, "png": png, "w": bw, "h": bh, "aspect": round(bw / bh, 3)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("moodboard")
    ap.add_argument("--sheet")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    src = Image.open(a.moodboard).convert("RGB")
    rows = [cut(src, *p) for p in PANELS]
    if a.sheet:
        thumbs = [Image.open(r["png"]).resize((256, max(1, round(256 / r["aspect"])))) for r in rows]
        W, x, y, rowh, pos = 1600, 0, 0, 0, []
        for t in thumbs:
            if x + t.width > W:
                x, y, rowh = 0, y + rowh + 6, 0
            pos.append((x, y)); x += t.width + 6; rowh = max(rowh, t.height)
        sheet = Image.new("RGB", (W, y + rowh), "white")
        for t, p in zip(thumbs, pos):
            sheet.paste(t, p)
        sheet.save(a.sheet)
    import json
    json.dump(rows, open(os.path.join(OUT, "panels.json"), "w"), indent=1)
    print(len(rows), "panels")


if __name__ == "__main__":
    main()
