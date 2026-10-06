#!/usr/bin/env python3
"""Hang a Cyberpunk vehicle sprite on the NCM node in OpenSpace (L325): a camera-facing billboard that follows whatever
NCM does to the node. The sprite is the player's own game art (prototypes/ncm_openspace/sprites.py), never shipped.
Usage: python prototypes/ncm_openspace/sprite_node.py [--part archer_hella__basic_player_01] [--cam-alt 60000]"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe import OpenSpace

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--part", default="archer_hella__basic_player_01")
ap.add_argument("--parent", default="NcmMachine")
ap.add_argument("--size", type=float, default=5.0)          # metres: a real car's length, before distance scaling
ap.add_argument("--apparent", type=float, default=0.06)     # fraction of the view it keeps when far away
ap.add_argument("--cam-alt", type=float, default=60000.0)
ap.add_argument("--lat", type=float, default=35.37)
ap.add_argument("--lon", type=float, default=-120.85)
a = ap.parse_args()

tex = os.path.join(ROOT, "tools", "openspace", "sprites", a.part + ".png").replace("\\", "/")
if not os.path.exists(tex):
    sys.exit("no sprite " + tex + " -- run sprites.py first")
o = OpenSpace()
ident = a.parent + "Sprite"
o.lua(f'if openspace.hasSceneGraphNode("{ident}") then openspace.removeSceneGraphNode("{ident}") end')
o.lua(f'''openspace.addSceneGraphNode({{
    Identifier = "{ident}", Parent = "{a.parent}",
    Renderable = {{ Type = "RenderablePlaneImageLocal", Size = {a.size}, Texture = "{tex}", Billboard = true,
        DistanceScalingSettings = {{ ScaleByDistance = true, ApparentSizeMultiplier = {a.apparent},
            ScaleByDistanceMaxHeight = 1.0E9, ScaleByDistanceMinHeight = 10 }} }},
    GUI = {{ Name = "NCM Machine sprite", Path = "/NCM" }}
}})''')
o.lua(f'openspace.navigation.jumpToGeo("Earth", {a.lat - 0.3}, {a.lon - 0.3}, {a.cam_alt})')
time.sleep(1.0)
o.lua(f'openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.Anchor", "{a.parent}")')
o.lua('openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.Aim", "")')
time.sleep(8)
print(o.lua('openspace.takeScreenshot(); return 1', want=True))
