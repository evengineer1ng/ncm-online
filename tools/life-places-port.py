#!/usr/bin/env python3
"""Port Night City's service points into ncm/core/world/places_data.lua (L237 M1, IDEA-764, L240).

Source: `references/world-pois/night_city_pois.json`, written by `tools/world-pois/build_registry.py` from the game's
own cooked map pins (docs/research/open77/NIGHT_CITY_POI_EXTRACTION.md). That folder is git-ignored because raw game
data is not redistributed. This tool carries DERIVED FACTS only -- a kind, a district, an area label and a position --
into NCM's own registry, the way the garages (paddock-garages-port.py) and the fuel stations (IDEA-704) were carried.
No journal path, pin name, entity id or raw record crosses over.

Rules, all deliberate:
  * Only `service_points` and `street_race` pins. Quest pins mark interiors, roofs and trigger volumes (the research
    note's limits), so bars and clubs wait for a curated or in-engine pass rather than being guessed from quest paths.
  * A service point's kind comes from the word in its own name (food, medic, ripperdoc, guns, ...). Names that are
    not public places (a locker, a casino cashier, a named dealer, sex work) are dropped.
  * District and area come from the name's own prefix (`wat_kab_` = Watson, Kabuki). Phantom Liberty `cz_` points
    are Dogtown. Anything else falls back to the nearest route node's region within 1,500 m, like the garages.
  * Pins of one kind within 20 m are one place (variants of the same shop).
  * Positions are rounded to 0.1 m and the list is sorted west-to-east, so ids are stable across re-extractions.
  * Every place ships unchecked: a pin is not a doorway. The runtime lets the owner mark a place good or bad in play.

Garages, fuel stations and Autofixers are NOT duplicated here: `world.places` merges them at runtime from
`paddock.garages_data`, `data.fuel_locations` and `economy.markets`.

The Lua file is GENERATED; `--check` fails when it no longer matches the source.

Usage:  python tools/life-places-port.py [--check]
"""
import argparse
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "references", "world-pois", "night_city_pois.json")
NODES = os.path.join(ROOT, "ncm", "core", "data", "nodes.lua")
OUT = os.path.join(ROOT, "ncm", "core", "world", "places_data.lua")

# First match wins, tested against the pin's own leaf name.
KIND_WORDS = [
    (r"black_market", "junk"),
    (r"food", "food"),
    (r"ripperdoc|ripdoc|rippdoc", "ripperdoc"),
    (r"medic", "clinic"),
    (r"gun|melee", "weapons"),
    (r"cloth", "clothing"),
    (r"junk", "junk"),
    (r"netrun", "netrunner"),
    (r"tech", "tech"),
    (r"fixer", "fixer"),
]
DROP = re.compile(r"prostitute|locker|cashier|heavy_hearts|camp_chang|spaceport")

DISTRICT = {"wat": "Watson", "wbr": "Westbrook", "hey": "Heywood", "std": "Santo Domingo", "pac": "Pacifica",
            "cct": "City Center", "bls": "Badlands", "cz": "Dogtown"}
AREA = {"kab": "Kabuki", "lch": "Little China", "nid": "Northside", "awf": "Arasaka Waterfront", "jpn": "Japantown",
        "hil": "Charter Hill", "gle": "the Glen", "rey": "Vista del Rey", "spr": "Wellsprings", "arr": "Arroyo",
        "rcr": "Rancho Coronado", "cvi": "Coastview", "wwd": "West Wind Estate", "cpz": "Corpo Plaza",
        "dtn": "Downtown", "ina": "the Badlands", "stadium": "the stadium", "con": "Dogtown",
        "monument": "Dogtown"}
RACE_AREA = {"badlands": ("Badlands", "the Badlands"), "big_race": ("City Center", "Downtown"),
             "city_center": ("City Center", "Downtown"), "santo_domingo": ("Santo Domingo", "Arroyo")}
MERGE_M = 20.0


def load_nodes():
    text = open(NODES, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+).*?region\s*=\s*\"([^\"]+)\"", text):
        out.append((float(m.group(1)), float(m.group(2)), m.group(3)))
    if not out:
        sys.exit("no nodes with regions parsed from " + NODES)
    return out


def nearest_region(x, y, nodes):
    best, best_d = None, 1e18
    for nx, ny, region in nodes:
        d = math.hypot(x - nx, y - ny)
        if d < best_d:
            best, best_d = region, d
    if best_d <= 1500:
        return best
    return "Badlands" if x > 1000 or y < -2500 else "Outskirts"


def classify(pin, nodes):
    path = pin.get("path") or ""
    leaf = path.split("/")[-1]
    if path.startswith("points_of_interest/street_race/"):
        for word, (district, area) in RACE_AREA.items():
            if word in leaf:
                return "meet", district, area
        return None
    if "/service_points/" not in "/" + path:
        return None
    if DROP.search(leaf):
        return None
    kind = next((k for pat, k in KIND_WORDS if re.search(pat, leaf)), None)
    if not kind:
        return None
    parts = leaf.split("_")
    district = DISTRICT.get(parts[0])
    area = AREA.get(parts[1]) if len(parts) > 1 else None
    if parts[0] == "cz" and parts[1] == "monument":
        area = "Dogtown"
    # `cz_` names every Phantom Liberty point, not only Dogtown's: only a point inside Dogtown's own bounds is
    # Dogtown (the garage port's rule). Live 2026-09-30: a Heywood food stall read as "a Dogtown food stall".
    if parts[0] == "cz":
        x, y = float(pin["x"]), float(pin["y"])
        if not (-2700 <= x <= -1100 and -3200 <= y <= -1800):
            district = nearest_region(x, y, nodes)
            area = district
    if not district:
        district = nearest_region(float(pin["x"]), float(pin["y"]), nodes)
    return kind, district, area or district


def build():
    if not os.path.exists(SRC):
        sys.exit("missing " + SRC + " -- run tools/world-pois/build_registry.py first (see the research note)")
    pins = json.load(open(SRC, encoding="utf-8"))
    nodes = load_nodes()
    rows = []
    for pin in pins:
        c = classify(pin, nodes)
        if not c:
            continue
        kind, district, area = c
        x, y, z = float(pin["x"]), float(pin["y"]), float(pin["z"])
        dup = next((r for r in rows if r["kind"] == kind and math.hypot(r["x"] - x, r["y"] - y) <= MERGE_M), None)
        if dup:
            continue
        rows.append({"kind": kind, "district": district, "area": area, "x": x, "y": y, "z": z})
    for r in rows:
        r["x"], r["y"], r["z"] = round(r["x"], 1), round(r["y"], 1), round(r["z"], 1)
    rows.sort(key=lambda r: (r["x"], r["y"], r["kind"]))
    lines = [
        "-- ncm-core data: world.places_data",
        "-- GENERATED by tools/life-places-port.py from the game's own map pins (IDEA-764). Do not edit by hand.",
        "-- Derived facts only: kind, district, area label, position. Every place is unchecked until an in-engine look.",
        "local Core = NcmCore",
        "",
        'Core.define("world.places_data", function(C)',
        "    local M = { version = \"0.1.0\" }",
        "    M.PLACES = {",
    ]
    for i, r in enumerate(rows, 1):
        lines.append('        { id = "s%03d", kind = "%s", district = "%s", area = "%s", x = %.1f, y = %.1f, z = %.1f },'
                     % (i, r["kind"], r["district"], r["area"], r["x"], r["y"], r["z"]))
    lines += ["    }", "    return M", "end)", ""]
    return "\n".join(lines), rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    text, rows = build()
    if args.check:
        have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if have != text:
            sys.exit("places_data.lua is stale: re-run tools/life-places-port.py")
        print("places_data.lua matches (%d places)" % len(rows))
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    by_kind, by_district = {}, {}
    for r in rows:
        by_kind[r["kind"]] = by_kind.get(r["kind"], 0) + 1
        by_district[r["district"]] = by_district.get(r["district"], 0) + 1
    print("wrote %d places" % len(rows))
    print("  kinds:     " + ", ".join("%s %d" % kv for kv in sorted(by_kind.items())))
    print("  districts: " + ", ".join("%s %d" % kv for kv in sorted(by_district.items())))


if __name__ == "__main__":
    main()
