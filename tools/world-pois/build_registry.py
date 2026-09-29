"""Build a Night City point-of-interest registry from the game's own cooked data (IDEA-736, L224).

Inputs are WolvenKit JSON conversions of four files extracted from the installed game (see
docs/research/open77/NIGHT_CITY_POI_EXTRACTION.md for the exact extract/convert commands):

  base/worlds/03_night_city/_compiled/default/03_night_city.poimappins   (ep1_1_nightcity.archive)
  base/worlds/03_night_city/_compiled/default/03_night_city.mappins      (ep1_1_nightcity.archive)
  base/journal/cooked_journal.journal and ep1/journal/cooked_journal.journal (ep1_2_gamedata.archive)

Each cooked pin names its journal entry only by `journalPathHash`. That hash is Murmur3-32 of the
'/'-joined journal entry path with seed 0x5EEDBA5E, which resolves 702/702 point-of-interest pins.

Outputs stay under references/world-pois/ (git-ignored: game data is not redistributed):
  night_city_pois.json  every pin: source, journal path, journal type, x, y, z
  garage_sites.json     garage/parking/workshop/Autofixer pins clustered into distinct sites

Usage: python tools/world-pois/build_registry.py [--root references/world-pois] [--cluster-m 25]
"""
import argparse
import collections
import json
import math
import os
import re

SEED = 0x5EEDBA5E
WORLD_REL = os.path.join('cooked', 'base', 'worlds', '03_night_city', '_compiled', 'default')
JOURNALS = [os.path.join('cooked', 'base', 'journal', 'cooked_journal.journal.json'),
            os.path.join('cooked', 'ep1', 'journal', 'cooked_journal.journal.json')]
GARAGE_RX = re.compile(r'garage|workshop|mechanic|autofixer|parking|chop|repair|junkyard|scrap', re.I)


def murmur3_32(text, seed=SEED):
    data = text.encode('utf-8')
    c1, c2, h, n = 0xcc9e2d51, 0x1b873593, seed, len(data) // 4 * 4
    for i in range(0, n, 4):
        k = int.from_bytes(data[i:i + 4], 'little')
        k = (k * c1) & 0xffffffff
        k = ((k << 15) | (k >> 17)) & 0xffffffff
        h ^= (k * c2) & 0xffffffff
        h = ((h << 13) | (h >> 19)) & 0xffffffff
        h = (h * 5 + 0xe6546b64) & 0xffffffff
    tail, k = data[n:], 0
    if len(tail) >= 3:
        k ^= tail[2] << 16
    if len(tail) >= 2:
        k ^= tail[1] << 8
    if tail:
        k ^= tail[0]
        k = (k * c1) & 0xffffffff
        k = ((k << 15) | (k >> 17)) & 0xffffffff
        h ^= (k * c2) & 0xffffffff
    h ^= len(data)
    h ^= h >> 16
    h = (h * 0x85ebca6b) & 0xffffffff
    h ^= h >> 13
    h = (h * 0xc2b2ae35) & 0xffffffff
    return h ^ (h >> 16)


def journal_entries(node, prefix, out):
    """Yield (path, type) for every journal entry; a path is the entry ids joined with '/'."""
    if isinstance(node, dict):
        path, t, nid = prefix, node.get('$type', ''), node.get('id')
        if isinstance(nid, str) and nid and t.startswith('gameJournal'):
            path = f'{prefix}/{nid}' if prefix else nid
            out.append((path, t))
        for v in node.values():
            if isinstance(v, (dict, list)):
                journal_entries(v, path, out)
    elif isinstance(node, list):
        for v in node:
            journal_entries(v, prefix, out)


def load(root, rel):
    return json.load(open(os.path.join(root, rel), encoding='utf-8'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=os.path.join('references', 'world-pois'))
    ap.add_argument('--cluster-m', type=float, default=25.0)
    a = ap.parse_args()

    entries = []
    for rel in JOURNALS:
        journal_entries(load(a.root, rel), '', entries)
    index = {murmur3_32(p): (p, t) for p, t in entries}

    rows = []
    poi = load(a.root, os.path.join(WORLD_REL, '03_night_city.poimappins.json'))['Data']['RootChunk']['cookedData']
    mp = load(a.root, os.path.join(WORLD_REL, '03_night_city.mappins.json'))['Data']['RootChunk']['cookedData']
    for src, pins in (('poi', poi), ('mappin', mp)):
        for pin in pins:
            path, jtype = index.get(pin['journalPathHash'], (None, None))
            v = pin['position']
            rows.append({'src': src, 'path': path, 'type': jtype, 'x': v['X'], 'y': v['Y'], 'z': v['Z']})
    resolved_poi = sum(1 for r in rows if r['src'] == 'poi' and r['path'])
    print(f'journal entries {len(entries)}; pins {len(rows)}; resolved {sum(1 for r in rows if r["path"])}; '
          f'points of interest resolved {resolved_poi}/{len(poi)}')

    garage = [r for r in rows if r['path'] and GARAGE_RX.search('/'.join(r['path'].split('/')[-2:]))]
    sites = []
    for r in garage:
        for s in sites:
            if math.dist((r['x'], r['y']), (s['x'], s['y'])) < a.cluster_m:
                s['refs'].append(r['path'])
                break
        else:
            sites.append({'x': r['x'], 'y': r['y'], 'z': r['z'], 'refs': [r['path']]})
    for s in sites:
        refs = s['refs']
        s['kind'] = ('autofixer' if any('autofixer' in p for p in refs) else
                     'parking' if all('parking' in p for p in refs) else
                     'workshop' if any('workshop' in p for p in refs) else 'garage')
    print(f'garage/workshop pins {len(garage)} -> {len(sites)} sites within {a.cluster_m:g} m:',
          dict(collections.Counter(s['kind'] for s in sites)))

    json.dump(rows, open(os.path.join(a.root, 'night_city_pois.json'), 'w'), indent=0)
    json.dump(sites, open(os.path.join(a.root, 'garage_sites.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
