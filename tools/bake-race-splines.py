#!/usr/bin/env python3
"""Bake NCM Pace's race splines: one engine race spline per race leg, loaded by ArchiveXL (L246, IDEA-788).

The engine's racer (`AIVehicleRacingCommand`) drives a world spline (`splineRef: NodeRef`) -- the same thing vanilla
street races drive (sq024's `worldRaceSplineNode`). Every Paddock race is a chain of authored nodes, so one spline per
ordered node pair covers every race. `ncm_pace_bake_legs` routes each pair over the game's own lane graph; this turns
those lines into `worldRaceSplineNode`s in open-world (Exterior level 6) sectors, a streaming block listing them, and the ArchiveXL
registration, then packs an archive with WolvenKit.

Each spline's ref is  $/mod/ncm_pace/#leg_<fromNodeId>__<toNodeId>  (Pace hashes the same string at runtime).

Usage:
  python tools/bake-race-splines.py --legs legs.jsonl --template quest_sector.json [--out dist/ncm_pace_race_splines]
    --legs      output of ncm/pace/build/Release/ncm_pace_bake_legs.exe <road-data> ncm/core/data/nodes.lua
    --template  any vanilla sector holding a worldRaceSplineNode, serialised by WolvenKit (structure only -- its
                geometry is not copied): base/worlds/03_night_city/_compiled/default/quest_5aab979acf00452f.streamingsector
"""
import argparse
import copy
import json
import math
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WKIT = os.path.join(ROOT, "ncm", "pace", "build", "wolvenkit-cli", "WolvenKit.CLI.exe")
DEPOT = "mod\\ncm_pace\\race_splines"
REF_PREFIX = "$/mod/ncm_pace/#leg_"
PER_SECTOR = 40                     # splines per sector: keeps each file small
CORRIDOR_M = 6.0                    # racing room each side of the line (vanilla: 7 m, 1.5-4 m in tight places)
KEEP_SPACING_M = 15.0               # thin the lane line: a point at least every 15 m...
KEEP_TURN_DEG = 8.0                 # ...or wherever the line turns
NODE_ID_BASE = 0x3F000000000        # our global node ids (see nodeData Id below)


def ref_of(a, b):
    return f"{REF_PREFIX}{a}__{b}"


def thin(points):
    out = [points[0]]
    for i in range(1, len(points) - 1):
        p, last, nxt = points[i], out[-1], points[i + 1]
        d = math.hypot(p[0] - last[0], p[1] - last[1])
        h1 = math.atan2(p[1] - last[1], p[0] - last[0])
        h2 = math.atan2(nxt[1] - p[1], nxt[0] - p[0])
        turn = abs((math.degrees(h2 - h1) + 180) % 360 - 180)
        if d >= KEEP_SPACING_M or (turn >= KEEP_TURN_DEG and d >= 3.0):
            out.append(p)
    out.append(points[-1])
    return out


def vec3(x, y, z):
    return {"$type": "Vector3", "X": x, "Y": y, "Z": z}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--legs", required=True)
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", default=os.path.join(ROOT, "dist", "ncm_pace_race_splines"))
    a = ap.parse_args()

    tpl = json.load(open(a.template, encoding="utf-8"))
    root = tpl["Data"]["RootChunk"]
    race = next(n for n in root["nodes"] if n["Data"]["$type"] == "worldRaceSplineNode")
    idx = root["nodes"].index(race)
    race_nd = next(e for e in root["nodeData"]["Data"] if e["NodeIndex"] == idx)

    legs = [json.loads(line) for line in open(a.legs, encoding="utf-8") if line.strip()]
    legs.sort(key=lambda l: (l["from"], l["to"]))
    src = os.path.join(a.out, "src")
    if os.path.isdir(a.out):
        shutil.rmtree(a.out)
    sector_dir = os.path.join(src, *DEPOT.split("\\"))
    os.makedirs(sector_dir)

    descriptors, total_pts, handle = [], 0, 1
    for s in range(0, len(legs), PER_SECTOR):
        chunk = legs[s:s + PER_SECTOR]
        sec = copy.deepcopy(tpl)
        r = sec["Data"]["RootChunk"]
        # Exterior, level 6 -- where vanilla keeps its long open-world splines (sq024's city-race speed spline lives in
        # exterior_-1_-1_0_6); our AlwaysLoaded sectors merged but their splines never resolved (KB-249).
        r["category"] = "Exterior"
        r["level"] = 6
        r["variantIndices"] = [0]
        r["variantNodes"] = []
        r["persistentNodes"] = []
        r["persistentNodeIndex"] = 0
        r["nodes"], r["nodeRefs"], nd = [], [], []
        for i, leg in enumerate(chunk):
            pts = thin(leg["points"])
            total_pts += len(pts)
            ox, oy, oz = pts[0]
            node = copy.deepcopy(race)
            handle += 1
            node["HandleId"] = str(handle)
            d = node["Data"]
            d["debugName"] = {"$type": "CName", "$storage": "string", "$value": "{ncm_leg_%s__%s}" % (leg["from"], leg["to"])}
            d["offsetDefault"] = CORRIDOR_M
            d["offsets"] = []
            d["speedChangeSections"] = [{"$type": "worldSpeedSplineNodeSpeedChangeSection", "end": 0, "start": 0, "targetSpeed_M_P_S": 100}]
            handle += 1
            d["splineData"]["HandleId"] = str(handle)
            sp = d["splineData"]["Data"]
            sp["looped"], sp["hasDirection"], sp["reversed"] = 0, 1, 0
            sp["points"] = [{"$type": "SplinePoint", "automaticTangents": 1, "continuousTangents": 1, "id": 0,
                             "position": vec3(round(x - ox, 3), round(y - oy, 3), round(z - oz, 3)),
                             "rotation": {"$type": "Quaternion", "i": 0, "j": 0, "k": 0, "r": 1},
                             "tangents": {"Elements": [vec3(0, 0, 0), vec3(0, 0, 0)]}} for (x, y, z) in pts]
            r["nodes"].append(node)
            ref = ref_of(leg["from"], leg["to"])
            r["nodeRefs"].append({"$type": "NodeRef", "$storage": "string", "$value": ref})
            e = copy.deepcopy(race_nd)
            e["NodeIndex"] = i
            e["Position"] = {"$type": "Vector4", "W": 0, "X": ox, "Y": oy, "Z": oz}
            e["Orientation"] = {"$type": "Quaternion", "i": 0, "j": 0, "k": 0, "r": 1}
            e["Pivot"] = vec3(ox, oy, oz)
            e["Bounds"] = {"$type": "Box", "Min": {"$type": "Vector4", "W": 0, "X": ox, "Y": oy, "Z": oz},
                           "Max": {"$type": "Vector4", "W": 0, "X": ox, "Y": oy, "Z": oz}}
            e["QuestPrefabRefHash"] = {"$type": "NodeRef", "$storage": "string", "$value": ref}
            # Node streaming flags as a vanilla ALWAYS-LOADED sector's ref'd nodes carry them (always_loaded_0: 1056 / 512 /
            # 15131.8 / 512). The quest template's 288 has the 0x100 bit every quest-sector node has and no
            # always-loaded node has: a node flagged quest-owned is never registered without its quest prefab, and both
            # racing and spline commands failed at once on these splines (KB-249).
            e["Uk10"], e["Uk11"], e["Uk12"] = 1056, 512, 0          # as vanilla exterior spline nodes
            e["MaxStreamingDistance"] = 15131.8018
            e["UkFloat1"] = float(round(leg["lengthM"]))         # vanilla: the spline's extent
            # A GLOBAL NODE ID. Every one of 32,106 vanilla Exterior nodes has one (42-bit, cook-allocated,
            # 0x248d0368450-0x24ac6e21f40 around Heywood); ours had 0, so the engine had no id to map a spline
            # ref to (KB-249). Unique per spline, above the vanilla range, still 42-bit.
            e["Id"] = str(NODE_ID_BASE + (s + i + 1) * 16)
            nd.append(e)
        r["nodeData"]["Data"] = nd
        name = f"legs_{s // PER_SECTOR:03d}.streamingsector"
        sec["Header"]["ArchiveFileName"] = os.path.join(sector_dir, name)
        json.dump(sec, open(os.path.join(sector_dir, name + ".json"), "w", encoding="utf-8"))
        descriptors.append({
            "$type": "worldStreamingSectorDescriptor",
            "blockIndex": {"$type": "worldStreamingBlockIndex", "oup": "Base", "rldGridCell": 0},
            "category": "Exterior",
            "data": {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": DEPOT + "\\" + name}, "Flags": "Soft"},
            "level": 6, "numNodeRanges": 1,
            "questPrefabNodeRef": {"$type": "NodeRef", "$storage": "uint64", "$value": "0"},
            "streamingBox": {"$type": "Box",
                             "Max": {"$type": "Vector4", "W": 1, "X": 64000.0, "Y": 64000.0, "Z": 64000.0},
                             "Min": {"$type": "Vector4", "W": 1, "X": -64000.0, "Y": -64000.0, "Z": -64000.0}},
            "variants": []})

    block = {"Header": copy.deepcopy(tpl["Header"]), "Data": copy.deepcopy(tpl["Data"])}
    block["Data"]["RootChunk"] = {"$type": "worldStreamingBlock", "cookingPlatform": "PLATFORM_PC", "descriptors": descriptors,
                                  "index": {"$type": "worldStreamingBlockIndex", "oup": "Base", "rldGridCell": 0}}
    block["Header"]["ArchiveFileName"] = os.path.join(sector_dir, "race_splines.streamingblock")
    json.dump(block, open(os.path.join(sector_dir, "race_splines.streamingblock.json"), "w", encoding="utf-8"))
    print(f"{len(legs)} splines, {total_pts} points, {len(descriptors)} sectors")

    # JSON -> CR2W, then pack
    subprocess.run([WKIT, "convert", "d", sector_dir], check=True)
    for f in os.listdir(sector_dir):
        if f.endswith(".json"):
            os.remove(os.path.join(sector_dir, f))
    pack_root = os.path.join(a.out, "ncm_pace_race_splines")
    shutil.move(os.path.join(src, "mod"), os.path.join(pack_root, "mod"))
    shutil.rmtree(src)
    subprocess.run([WKIT, "pack", pack_root, "-o", a.out], check=True)
    with open(os.path.join(a.out, "ncm_pace_race_splines.archive.xl"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# NCM Pace race splines (L246, IDEA-788): one engine race spline per race leg, open-world (Exterior level 6).\n")
        f.write("streaming:\n  blocks:\n    - " + DEPOT + "\\race_splines.streamingblock\n")
    print("archive + .xl in", a.out)


if __name__ == "__main__":
    main()
