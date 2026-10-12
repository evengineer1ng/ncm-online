#!/usr/bin/env python3
"""corpus.json + the render manifest -> the director's data file (doc 59 §3-§5).

    python ncm/radio/tools/build_corpus_lua.py [--manifest D:/ncm-radio/pack/manifest.json]

Writes `ncm/online/resources/ncm_radio/server/corpus_data.lua` (global `NcmRadioCorpus`). Every beat and line is
emitted -- dormant beats included -- with each line as the list of parts the director strings together: a rendered
clip key (with its length) or a slot (with its class). A part whose clip is not rendered yet carries ms = 0; the
director never airs a beat with such a part. `lex` lists every rendered lexicon clip, so the director binds a slot
only to a value somebody has actually voiced.
"""
import argparse
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'ncm', 'radio', 'voice'))
import render  # noqa: E402  (parts_of, speakable, speaker_slug: the same split the render used)

LUA_KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local',
                'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}
CORPUS = os.path.join(REPO, 'ncm', 'radio', 'corpus', 'corpus.json')
SLOTS = os.path.join(REPO, 'ncm', 'radio', 'corpus', 'slots.json')
CAST = os.path.join(REPO, 'ncm', 'radio', 'voice', 'cast.json')
OUT = os.path.join(REPO, 'ncm', 'online', 'resources', 'ncm_radio', 'server', 'corpus_data.lua')


def lua(v, indent=''):
    if v is None:
        return 'nil'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua(x) for x in v) + '}'
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', k) and k not in LUA_KEYWORDS else '[' + lua(k) + ']'
            parts.append('%s=%s' % (key, lua(x)))
        return '{' + ','.join(parts) + '}'
    raise TypeError(type(v))


def week_text():
    """NCM's own public Week sentences: Moody's faces (id -> line, tone) and the Week's PA steps (id -> text), read from
    ncm/core/week so they never drift. Tone is the bible §28 family a face belongs to, from its effects."""
    core = os.path.join(REPO, 'ncm', 'core', 'week')
    moody, steps = {}, {}
    src = io.open(os.path.join(core, 'moody.lua'), encoding='utf-8').read()
    for m in re.finditer(r'\{\s*id\s*=\s*"([a-z_]+)",\s*name\s*=\s*"([^"]+)"(.*?)line\s*=\s*"([^"]+)"', src, re.S):
        fid, name, body, line = m.group(1), m.group(2), m.group(3), m.group(4)
        tone = 'weird'
        if 'purse' in body:
            tone = 'economic'
        if re.search(r'limit\s*=\s*1\.[1-9]', body) or re.search(r'policeCap\s*=\s*-', body) or re.search(r'calendar\s*=\s*tiers\(ALL,\s*0\.', body):
            tone = 'expansive'
        if re.search(r'limit\s*=\s*0\.', body) or re.search(r'policeCap\s*=\s*1', body) or re.search(r'calendar\s*=\s*tiers\(ALL,\s*1\.', body):
            tone = 'restrictive'
        moody[fid] = {'name': name, 'line': line, 'tone': tone}
    src = io.open(os.path.join(core, 'curve.lua'), encoding='utf-8').read()
    for m in re.finditer(r'\{\s*id\s*=\s*"([a-z_]+)".*?pa\s*=\s*"([^"]+)"', src, re.S):
        steps[m.group(1)] = m.group(2)
    return moody, steps


HANDOFF_NAMES = {'Tommy': 'TOMMY', 'Imani': 'IMANI', 'Nia': 'NIA', 'Jules': 'JULES', 'Julian': 'JULES',
                 'Celeste': 'CELESTE', 'Darnell': 'DARNELL', 'Mara': 'MARA'}
HANDOFF = re.compile(r"(?:\b(?:back to|over to|throw (?:it )?to|let's go to|going back to|going to)\s+(%s)\b"
                     r"|^(%s)\?$|\b(%s)[,.]? (?:you there|go ahead|take it|what have you got|what do you have)\b)"
                     % (('|'.join(HANDOFF_NAMES),) * 3), re.I)


def handoff_of(b):
    """The voice a beat's last line hands to, or None (bible §76: a deliberate handoff is seen through)."""
    lines = [it for it in b['items'] if it['kind'] == 'line']
    if not lines:
        return None
    text = lines[-1]['say'].strip()
    m = HANDOFF.search(text) or HANDOFF.search(text.split('. ')[-1].strip())
    if not m:
        return None
    who = HANDOFF_NAMES[next(g for g in m.groups() if g).capitalize()]
    return who if who != lines[-1]['speaker'] else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', default='D:/ncm-radio/pack/manifest.json')
    ap.add_argument('--out', default=OUT)
    a = ap.parse_args()
    corpus = render.load(CORPUS)
    slots = render.load(SLOTS)
    cast = render.load(CAST)
    raw = render.load(a.manifest) if os.path.exists(a.manifest) else {}
    # only clips voiced with the speaker's CURRENT pick count: a recast speaker's old clips (and an uncast speaker's)
    # must never air (2026-10-08: the first Mara designs were noise)
    manifest = {}
    for k, e in raw.items():
        sp = e.get('speaker') or ''
        if not sp:
            manifest[k] = e                     # stingers
            continue
        v = int(k.rsplit('@', 1)[1]) if '@' in k else 0
        picks = render.voices_of(cast, sp) if sp in cast['speakers'] else []
        if v < len(picks) and e.get('voice', 'cand0.wav') == picks[v]:
            manifest[k] = e
    cls = {s: c for c, names in slots['classes'].items() for s in names}
    stingers = cast['stingers']

    beats, ready, lines_total, lines_ready = [], 0, 0, 0
    for b in corpus['beats']:
        out_lines, beat_ok = [], True
        for it in b['items']:
            if it['kind'] == 'cue':
                sid = stingers.get(it['cue'])
                if sid:
                    out_lines.append({'cue': 'sting/' + sid, 'ms': manifest.get('sting/' + sid, {}).get('ms', 0)})
                continue
            lines_total += 1
            parts, n, ok = [], 0, True
            if not it['slots']:
                ms = manifest.get(it['id'], {}).get('ms', 0)
                parts.append({'k': it['id'], 'ms': ms})
                ok = ms > 0
            else:
                for p in render.parts_of(it['say']):
                    if isinstance(p, dict):
                        parts.append({'slot': p['slot'], 'cls': cls.get(p['slot'], 'abstract')})
                        continue
                    n += 1
                    if not render.speakable(p):
                        continue
                    key = '%s~%d' % (it['id'], n)
                    ms = manifest.get(key, {}).get('ms', 0)
                    parts.append({'k': key, 'ms': ms})
                    ok = ok and ms > 0
            lines_ready += 1 if ok else 0
            nv = len(render.voices_of(cast, it['speaker']))
            if nv > 1:
                # several voices for this role (different drivers): each clip also exists as key@1, key@2 ...
                for part in parts:
                    if 'k' in part:
                        part['vms'] = [manifest.get(render.variant_key(part['k'], v), {}).get('ms', 0) for v in range(1, nv)]
            line = {'id': it['id'], 'sp': it['speaker'], 'parts': parts, 'w': len(it['say'].split())}
            if nv > 1:
                line['nv'] = nv
            if it['pure_slot']:
                line['optional'] = True
            if it['example']:
                line['example'] = True
            if not ok and not it['pure_slot']:
                beat_ok = False
            out_lines.append(line)
        g = dict(b['gates'])
        handoff = handoff_of(b)
        for k in ('day', 'hour', 'week_race', 'player_starts'):
            if k in g and isinstance(g[k], (list, tuple)):
                g[k] = list(g[k])
        beats.append({'id': b['id'], 'section': b['section'] or 0, 'trigger': b['trigger'], 'gates': g, 'segment': b['segment'],
                      'treatment': b['treatment'], 'lead': b['lead'], 'lines': out_lines,
                      'ready': beat_ok, 'example': b['example'], 'shapes': b.get('shapes') or [],
                      'direction': b.get('direction', 'neutral'), 'gives': b.get('motif_gives') or [],
                      'needs': b.get('motif_needs') or []})
        if handoff:
            # the beat ends by passing to another voice ("Tommy?"): it may only air when that voice can answer next
            beats[-1]['handoff'] = handoff
        ready += 1 if (beat_ok and b['trigger'] != 'dormant') else 0

    moody, steps = week_text()
    lex = {k: v['ms'] for k, v in manifest.items() if k.startswith('lex/')}
    stings = {k: v['ms'] for k, v in manifest.items() if k.startswith('sting/')}
    pack_version = ''
    if os.path.exists(a.manifest):
        import hashlib
        pack_version = hashlib.sha256(open(a.manifest, 'rb').read()).hexdigest()[:12]

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with io.open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERATED by ncm/radio/tools/build_corpus_lua.py from the authoring bible; do not edit by hand.\n')
        f.write('-- %d beats, %d lines (%d performable), %d live beats ready to air; pack %s.\n'
                % (len(beats), lines_total, lines_ready, ready, pack_version or 'none'))
        f.write('NcmRadioCorpus = {\n')
        f.write('  source_sha256 = %s,\n' % lua(corpus['source_sha256']))
        f.write('  pack = %s,\n' % lua(pack_version))
        f.write('  gap_ms = %d,\n' % cast.get('gap_ms', 260))
        f.write('  beats = {\n')
        for b in beats:
            f.write('    ' + lua(b) + ',\n')
        f.write('  },\n')
        f.write('  lex = ' + lua(lex) + ',\n')
        f.write('  stings = ' + lua(stings) + ',\n')
        f.write('  speakers = ' + lua({sp: render.speaker_slug(sp) for sp in cast['speakers']}) + ',\n')
        f.write('  moody = ' + lua(moody) + ',\n')
        f.write('  steps = ' + lua(steps) + ',\n')
        f.write('}\n')
    print('wrote %s: %d beats, %d/%d lines performable, %d live beats ready, %d lexicon clips, pack %s'
          % (os.path.relpath(a.out, REPO), len(beats), lines_ready, lines_total, ready, len(lex), pack_version or '-'))


if __name__ == '__main__':
    main()
