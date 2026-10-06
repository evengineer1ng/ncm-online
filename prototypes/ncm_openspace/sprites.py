#!/usr/bin/env python3
"""Cyberpunk vehicle sprites for the NCM universe (L325): crop the game's own vehicle icon atlas into one PNG per car.

Inputs are produced from the player's OWN game files by WolvenKit (never shipped -- game art is not redistributable):
  WolvenKit.CLI uncook <game>/archive/pc/content -o tools/openspace/sprites_raw -w "*vehicles_icons*" -s
  WolvenKit.CLI export .../vehicles_icons.xbm -o tools/openspace/sprites_png --uext png -gp <game>
Then:  python prototypes/ncm_openspace/sprites.py   -> tools/openspace/sprites/<part>.png + index.json
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS_JSON = os.path.join(ROOT, r"tools\openspace\sprites_raw\base\gameplay\gui\common\icons\vehicles_icons.inkatlas.json")
ATLAS_PNG = os.path.join(ROOT, r"tools\openspace\sprites_png\vehicles_icons.png")
OUT = os.path.join(ROOT, r"tools\openspace\sprites")


def main():
    atlas = json.load(open(ATLAS_JSON, encoding="utf-8"))
    parts = atlas["Data"]["RootChunk"]["slots"]["Elements"][0]["parts"]
    img = Image.open(ATLAS_PNG).convert("RGBA")
    w, h = img.size
    os.makedirs(OUT, exist_ok=True)
    index = {}
    for p in parts:
        name = p["partName"]["$value"]
        uv = p["clippingRectInUVCoords"]
        box = (round(uv["Left"] * w), round(uv["Top"] * h), round(uv["Right"] * w), round(uv["Bottom"] * h))
        if box[2] <= box[0] or box[3] <= box[1]:
            continue
        crop = img.crop(box)
        bb = crop.getbbox()               # trim transparent margins
        if bb:
            crop = crop.crop(bb)
        path = os.path.join(OUT, name + ".png")
        crop.save(path)
        index[name] = {"file": name + ".png", "size": list(crop.size)}
    json.dump(index, open(os.path.join(OUT, "index.json"), "w", encoding="utf-8"), indent=1, sort_keys=True)
    print(f"{len(index)} sprites -> {OUT}")


if __name__ == "__main__":
    sys.exit(main())
