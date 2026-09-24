#!/usr/bin/env python
"""
Generate simple, clearly differentiated placeholder team liveries for the RB15 from the region masks in
uv-templates/masks/ (corrected UV orientation, validated in game 2026-09-18).

    uv run --with pillow,numpy tools/gen_placeholder_liveries.py            # all teams
    uv run --with pillow,numpy tools/gen_placeholder_liveries.py herrera raven

Writes liveries/rb15_ext_<team>.png (4096x4096 RGB). The artist's real file later overwrites the same name.
Text orientation per panel follows uv-templates/masks/text_anchors.json (left side upright, right side 180,
rear-wing rear face 180, front face upright, nose/endplate strips rotated).
"""
import os, sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__)); PROJ = os.path.dirname(HERE)
MASKS = os.path.join(PROJ, 'uv-templates', 'masks'); OUT = os.path.join(PROJ, 'liveries')
S = 4096

# team -> (base, accent, secondary, text colour, display name)
TEAMS = {
    'herrera':       ((92, 15, 26),   (212, 175, 55),  (20, 16, 18),   (240, 225, 180), 'HERRERA'),
    'mizutani':      ((240, 240, 245),(30, 90, 200),   (20, 40, 90),   (30, 60, 140),   'MIZUTANI'),
    'quadra':        ((18, 18, 20),   (255, 110, 0),   (60, 60, 64),   (255, 140, 40),  'QUADRA'),
    'thorton':       ((18, 40, 90),   (200, 205, 210), (10, 20, 45),   (230, 235, 240), 'THORTON'),
    'archer':        ((20, 90, 50),   (10, 12, 12),    (30, 130, 70),  (220, 240, 220), 'ARCHER'),
    'spunky_monkey': ((110, 40, 170), (170, 255, 40),  (60, 20, 100),  (200, 255, 120), 'SPUNKY MONKEY'),
    'kimiko':        ((235, 60, 140), (20, 18, 22),    (250, 120, 180),(255, 240, 250), 'KIMIKO'),
    'yorinobu':      ((190, 20, 30),  (245, 245, 245), (120, 10, 20),  (255, 255, 255), 'YORINOBU'),
    'raven':         ((15, 15, 18),   (0, 220, 230),   (30, 32, 36),   (0, 240, 250),   'RAVEN'),
}

def load_mask(name):
    return np.array(Image.open(os.path.join(MASKS, name + '.png')).convert('L')) > 127

def font(size):
    for f in ('impact.ttf', 'arialbd.ttf', 'arial.ttf'):
        try: return ImageFont.truetype(f, size)
        except OSError: pass
    return ImageFont.load_default()

def draw_text_in_box(canvas, box, text, rot, fill, outline=None):
    """Draw text sized to fit box, rotated by rot degrees CCW (0/90/180/270), pasted into canvas."""
    x0, y0, x1, y1 = box; bw, bh = x1 - x0, y1 - y0
    tw, th = (bw, bh) if rot in (0, 180) else (bh, bw)          # text drawn horizontally then rotated
    size = int(th * 0.8)
    f = font(size)
    while size > 8:
        f = font(size); l, t, r, b = f.getbbox(text)
        if r - l <= tw * 0.94 and b - t <= th * 0.9: break
        size -= 4
    tile = Image.new('RGBA', (tw, th), (0, 0, 0, 0)); d = ImageDraw.Draw(tile)
    l, t, r, b = f.getbbox(text); d.text(((tw - (r - l)) / 2 - l, (th - (b - t)) / 2 - t), text, font=f, fill=fill,
                                        stroke_width=max(1, size // 30) if outline else 0, stroke_fill=outline)
    if rot: tile = tile.rotate(rot, expand=True)
    canvas.alpha_composite(tile, (x0, y0))

def build(team):
    base, accent, second, textc, label = TEAMS[team]
    m = {n: load_mask(n) for n in ('front_wing', 'rear_wing', 'mirrors', 'nose', 'susp', 'floor', 'sidepod_l',
                                   'sidepod_r', 'cockpit_halo', 'engine_cover', 'chassis_sides', 'diffuser', 'other')}
    img = np.zeros((S, S, 3), np.uint8); img[:] = base                     # margins = base colour (no mip bleed)
    for n in ('front_wing', 'rear_wing', 'diffuser'): img[m[n]] = second
    for n in ('mirrors', 'susp', 'cockpit_halo'): img[m[n]] = accent
    # accent stripe across the sidepods / engine cover: a diagonal band in atlas space limited to those masks
    yy, xx = np.mgrid[0:S, 0:S]
    band = ((xx + yy * 0.15) % 900) < 260
    for n in ('sidepod_l', 'sidepod_r', 'engine_cover'): img[m[n] & band] = accent
    im = Image.fromarray(img).convert('RGBA')
    anchors = json.load(open(os.path.join(MASKS, 'text_anchors.json')))
    for key in ('sidepod_l_main', 'sidepod_r_main', 'rear_wing_rear', 'rear_wing_front', 'nose_top',
                'fw_endplate_l', 'fw_endplate_r'):
        a = anchors[key]
        # solid backing plate so text stays legible over the stripe
        x0, y0, x1, y1 = a['box']; ImageDraw.Draw(im).rectangle([x0 - 12, y0 - 12, x1 + 12, y1 + 12], fill=base + (255,))
        draw_text_in_box(im, a['box'], label, a['rot'], textc + (255,), outline=None)
    for key in ('sidepod_l_sub', 'sidepod_r_sub'):
        a = anchors[key]; draw_text_in_box(im, a['box'], 'NCM FORMULA  //  ' + label, a['rot'], accent + (255,))
    out = os.path.join(OUT, f'rb15_ext_{team}.png'); im.convert('RGB').save(out); print('wrote', out)

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    teams = sys.argv[1:] or list(TEAMS)
    for t in teams: build(t)
