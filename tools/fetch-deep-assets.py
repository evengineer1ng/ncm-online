#!/usr/bin/env python3
"""L326: the local assets NCM Deep draws with (ncm_world/web/deep/, gitignored).

  earth.jpg            NASA Blue Marble, topography + bathymetry, Dec 2004, 5400 x 2700 (public domain, NASA Visible Earth)
  sprites/machine.png  the player's Machine as a sprite, cropped from THEIR OWN game files (prototypes/ncm_openspace/sprites.py);
                       game art is never committed or redistributed

Usage: python tools/fetch-deep-assets.py [--sprite archer_hella__basic_player_01]
"""
import argparse
import os
import shutil
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "ncm", "online", "resources", "ncm_world", "web", "deep")
EARTH = "https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/world.topo.bathy.200412.3x5400x2700.jpg"

ap = argparse.ArgumentParser()
ap.add_argument("--sprite", default="archer_hella__basic_player_01")
a = ap.parse_args()

os.makedirs(os.path.join(OUT, "sprites"), exist_ok=True)
earth = os.path.join(OUT, "earth.jpg")
if not os.path.exists(earth):
    urllib.request.urlretrieve(EARTH, earth)
print("earth.jpg", os.path.getsize(earth), "bytes")
src = os.path.join(ROOT, "tools", "openspace", "sprites", a.sprite + ".png")
if os.path.exists(src):
    shutil.copyfile(src, os.path.join(OUT, "sprites", "machine.png"))
    print("sprites/machine.png <-", a.sprite)
else:
    print("no sprite", src, "-- run prototypes/ncm_openspace/sprites.py first (the page draws without one)")
