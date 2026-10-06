#!/usr/bin/env python3
"""Put OpenSpace's camera next to the NCM probe node over Night City's place on Earth, in daylight, and screenshot it.
Usage: python prototypes/ncm_openspace/view.py [--alt 12000] [--utc 2026-10-05T20:00:00]"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe import OpenSpace

ap = argparse.ArgumentParser()
ap.add_argument("--lat", type=float, default=35.37)
ap.add_argument("--lon", type=float, default=-120.85)
ap.add_argument("--alt", type=float, default=12000.0)
ap.add_argument("--utc", default="2026-10-05T20:00:00")   # 13:00 in California: the coast in daylight
ap.add_argument("--node", default="NcmMachine")
ap.add_argument("--wait", type=float, default=6.0)
a = ap.parse_args()

o = OpenSpace()
o.lua(f'openspace.time.setTime("{a.utc}")')
o.lua(f'openspace.navigation.jumpToGeo("Earth", {a.lat - 0.05}, {a.lon - 0.05}, {a.alt})')
time.sleep(1.0)
o.lua(f'openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.Anchor", "{a.node}")')
o.lua('openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.Aim", "")')
time.sleep(a.wait)   # let the globe tiles stream in
print(o.lua('openspace.takeScreenshot(); return openspace.absPath("${SCREENSHOTS}")', want=True))
