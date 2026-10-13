"""Re-path Drive an Aerial Vehicle's car-class Atlus (MIT, tidusmd0806/CP2077-DriveAerialVehicle) to NCM AV paths.

Inputs are WolvenKit 8.20 JSON (`convert serialize`) of DAV's files; output is ncm/av/source, which
tools/build-ncm-av.py turns back into game files and packs. Usage:
    python tools/ncm-av-repath.py <dir with DAV *.json> ncm/av/source
"""
import json
import os
import sys

MAP = {
    r"base\dav\atlus\zetatech_atlus_ep1_dav.app": r"ncm\av\atlus\ncm_atlus_ep1.app",
    r"base\dav\atlus\zetatech_atlus_dav.app": r"ncm\av\atlus\ncm_atlus.app",
    r"base\dav\vfx\v_av_manticore_thrusters_dav.effect": r"ncm\av\vfx\ncm_av_thrusters.effect",
}
FILES = {
    "av_zetatech_atlus_basic_02_dav.ent.json": "ncm/av/atlus/ncm_atlus.ent.json",
    "zetatech_atlus_dav.app.json": "ncm/av/atlus/ncm_atlus.app.json",
    "zetatech_atlus_ep1_dav.app.json": "ncm/av/atlus/ncm_atlus_ep1.app.json",
    "v_av_manticore_thrusters_dav.effect.json": "ncm/av/vfx/ncm_av_thrusters.effect.json",
}


def repath(o):
    if isinstance(o, dict):
        return {k: repath(v) for k, v in o.items()}
    if isinstance(o, list):
        return [repath(v) for v in o]
    if isinstance(o, str) and o in MAP:
        return MAP[o]
    return o


def strings(o):
    if isinstance(o, dict):
        for v in o.values():
            yield from strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from strings(v)
    elif isinstance(o, str):
        yield o


src, out = sys.argv[1], sys.argv[2]
for s, d in FILES.items():
    j = json.load(open(os.path.join(src, s), encoding="utf-8"))
    j = repath(j)
    j.setdefault("Header", {})["ArchiveFileName"] = d[:-5].replace("/", "\\")
    left = [x for x in strings(j) if "\\dav\\" in x]
    assert not left, (s, left[:3])
    p = os.path.join(out, d)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="") as f:
        json.dump(j, f, indent=2)
    print(d)
