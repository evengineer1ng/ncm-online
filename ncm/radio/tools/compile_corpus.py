#!/usr/bin/env python3
"""Compile the Race Week Live authoring bible into the station corpus (L348, doc 59 §2).

    python ncm/radio/tools/compile_corpus.py [bible.md] [out.json]

Every heading that holds dialogue becomes a BEAT. Every `**SPEAKER:**` paragraph in the bible becomes a LINE of
exactly one beat, verbatim (the raw text is kept; `say` is the same words with markdown removed). Stinger cues stay
in place. The writer's notes under a beat (Eligibility, Purpose, "Use when ...") are kept beside it, never spoken.

The compiler refuses to write if a single speaker paragraph in the bible did not land in the corpus: the owner's
instruction is that no line is spared.

Ids are stable across re-compiles: a beat's id comes from its authored code (`FINISH-NORMAL-A`, `D1-H0-01`) or
from its section number and title; a line's id is `<beat>#<ordinal>`. `key` is a content hash (speaker + words) so
a re-render only touches lines whose words changed.
"""
import hashlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, os.path.join(HERE, '..', 'corpus'))
sys.path.insert(0, HERE)
import families  # noqa: E402
DEFAULT_BIBLE = os.path.join(REPO, 'docs', 'ncm-online', 'radio', 'RACE_WEEK_RADIO_BIBLE.md')
DEFAULT_OUT = os.path.join(REPO, 'ncm', 'radio', 'corpus', 'corpus.json')

HEADING = re.compile(r'^(#{1,4})\s+(.*?)\s*$')
# Two speaker formats: `**MARA:** words` (passes up to §175) and plain `MARA: words` (expansion pass II, §210+; and two
# blockquoted examples in §51). The plain form is accepted only for the cast's own names so prose like "Note:" is not.
CAST = r'(?:MARA|JULES|TOMMY|NIA|IMANI|CELESTE|DARNELL|DRIVER|SECOND REMOTE FEED)(?:/[A-Z]+)*'
SPEAKER = re.compile(r'^(> )?(?:\*\*([A-Z][A-Z .()/"-]+):\*\*|(' + CAST + r'):)\s*(.*)$')
CUE = re.compile(r'^\*\*([A-Z][A-Z ]*(?:STINGER|BED|SILENCE|MUSIC)[A-Z ]*)\*\*\s*$')
SLOT = re.compile(r'\{([A-Z0-9_]+)\}')
CODE = re.compile(r'^(?:Beat\s+)?([A-Z0-9]+(?:-[A-Z0-9]+)+)\b')
SECTION = re.compile(r'^(\d+)\.')

# Facts the runtime binds directly from simulation state. Everything else in braces is an ABSTRACT slot: a
# sentence-sized fact that needs its own authored fill (doc 59 §4); a line that is nothing but one is optional.
CONCRETE = {
    'DRIVER', 'WINNER', 'PLAYER_NAME', 'MACHINE', 'EVENT_NAME', 'LOCATION', 'MARGIN', 'EVENT', 'P2', 'P3', 'LEADER',
    'POSITION', 'DAY', 'FAVORITE', 'A', 'B', 'ATTACKER', 'TIME', 'TEAM', 'CHAMPION', 'TARGET', 'FIELD_SIZE',
    'DRIVER_A', 'DRIVER_B', 'EVENT_A', 'EVENT_B', 'DRIVER_OR_TEAM', 'CHASER', 'SPONSOR', 'SERIES', 'OTHER_DRIVER',
    'NEW_WINNER', 'GAP', 'WINNER_A', 'WINNER_B', 'TITLE', 'POLE', 'COUNT', 'ROUTE', 'CLASS', 'LAPS', 'POINTS',
    'PURSE', 'BUYER', 'SELLER', 'PRICE', 'PART', 'HOUR', 'WEATHER', 'WEATHER_STATE', 'RECORD_TIME', 'OLD_RECORD',
    'NEXT_EVENT', 'START_TIME', 'DISTRICT', 'DESTINATION', 'ORIGIN', 'ALTITUDE', 'DURATION', 'ODDS', 'STREAK',
    'WINS', 'PODIUMS', 'STARTS', 'DNFS', 'RIVAL', 'VICTIM', 'HACKER', 'HACK', 'ORG', 'MANUFACTURER', 'PREVIOUS_WINNER',
}

TTS_STRIP = re.compile(r'[`*]')


def spoken_text(text):
    """The words without markdown: backticks and asterisks go; an underscore goes only outside a {SLOT}."""
    out, depth = [], 0
    for ch in TTS_STRIP.sub('', text):
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth = max(0, depth - 1)
        if ch == '_' and depth == 0:
            continue
        out.append(ch)
    return ''.join(out)


def slug(text, limit=48):
    s = re.sub(r'[^A-Za-z0-9]+', '-', text).strip('-').upper()
    return s[:limit].rstrip('-') or 'UNTITLED'


def clean_title(text):
    t = text.replace('\\', '')
    t = re.sub(r'\s+---\s+', ' - ', t)
    return t.strip()


def compile_bible(path):
    raw = io.open(path, encoding='utf-8').read()
    lines = raw.split('\n')
    headings = []            # stack of (level, title, line_no)
    section = None           # the top-level "# N." number
    nodes = {}               # heading line_no -> node
    order = []
    node = None

    def current():
        nonlocal node
        if node is None:
            node = {'heading': '(preamble)', 'path': [], 'section': None, 'line': 0, 'items': [], 'notes': []}
            nodes[0] = node
            order.append(0)
        return node

    i, n = 0, len(lines)
    expected = 0
    while i < n:
        line = lines[i]
        h = HEADING.match(line)
        if h:
            level = len(h.group(1))
            title = h.group(2)
            if level == 1:
                m = SECTION.match(title)
                if m:
                    section = int(m.group(1))
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, title, i + 1))
            node = {'heading': title, 'path': [t for _, t, _ in headings], 'section': section, 'line': i + 1,
                    'level': level, 'items': [], 'notes': []}
            nodes[i + 1] = node
            order.append(i + 1)
            i += 1
            continue
        s = SPEAKER.match(line)
        if s:
            expected += 1
            quoted = bool(s.group(1))
            speaker = s.group(2) or s.group(3)
            words = [s.group(4)]
            start = i + 1
            i += 1
            while i < n and lines[i].strip() and not SPEAKER.match(lines[i]) and not HEADING.match(lines[i]):
                nxt = lines[i]
                if quoted and nxt.startswith('>'):
                    nxt = nxt[1:].lstrip()
                words.append(nxt.strip())
                i += 1
            text = ' '.join(w for w in words if w).strip()
            current()['items'].append({'kind': 'line', 'speaker': speaker.strip(), 'text': text,
                                       'example': quoted, 'src_line': start})
            continue
        c = CUE.match(line.strip())
        if c:
            current()['items'].append({'kind': 'cue', 'cue': c.group(1).strip(), 'src_line': i + 1})
            i += 1
            continue
        if line.strip() and line.strip() != '-' * len(line.strip()):
            para = [line.strip()]
            i += 1
            while i < n and lines[i].strip() and not SPEAKER.match(lines[i]) and not HEADING.match(lines[i]) \
                    and not CUE.match(lines[i].strip()):
                para.append(lines[i].strip())
                i += 1
            current()['notes'].append(' '.join(para))
            continue
        i += 1

    beats, used = [], set()
    total = 0
    for key in order:
        nd = nodes[key]
        spoken = [it for it in nd['items'] if it['kind'] == 'line']
        if not spoken:
            continue
        code = CODE.match(nd['heading'])
        if code and code.group(1).count('-') >= 1 and not re.match(r'^D\d+$', code.group(1)):
            bid = code.group(1)
        else:
            bid = 'S%s-%s' % (nd['section'] if nd['section'] is not None else 0, slug(nd['heading']))
        base, k = bid, 2
        while bid in used:
            bid = '%s~%d' % (base, k)
            k += 1
        used.add(bid)
        items, ordinal = [], 0
        for it in nd['items']:
            if it['kind'] == 'cue':
                items.append(it)
                continue
            ordinal += 1
            text = it['text']
            slots = SLOT.findall(text)
            say = spoken_text(text)
            bare = SLOT.sub('', say)
            pure = bool(slots) and not re.search(r'[A-Za-z0-9]', bare)
            abstract = sorted({x for x in slots if x not in CONCRETE})
            speakers = [p.strip() for p in it['speaker'].split('/')]
            items.append({
                'kind': 'line', 'id': '%s#%02d' % (bid, ordinal), 'speaker': speakers[0],
                'alt_speakers': speakers[1:], 'text': text, 'say': say, 'slots': slots, 'abstract': abstract,
                'pure_slot': pure, 'example': it['example'], 'src_line': it['src_line'],
                'key': hashlib.sha1(('%s|%s' % (speakers[0], say)).encode('utf-8')).hexdigest()[:16],
            })
            total += 1
        notes = nd['notes']
        trigger, gates = families.classify({'id': bid})
        if trigger is None:
            raise SystemExit('REFUSED: no trigger rule claims beat %s (%s)' % (bid, nd['heading']))
        spoken_items = [x for x in items if x['kind'] == 'line']
        speakers_in = []
        for x in spoken_items:
            if x['speaker'] not in speakers_in:
                speakers_in.append(x['speaker'])
        segment = next((families.SEGMENT_BY_SPEAKER[s] for s in speakers_in if s in families.SEGMENT_BY_SPEAKER), 'studio')
        words = sum(len(x['say'].split()) for x in spoken_items)
        abstract_inline = sorted({a for x in spoken_items if not x['pure_slot'] for a in x['abstract']})
        elig = next((x for x in notes if x.startswith('**Eligibility:**')), None)
        beats.append({
            'id': bid, 'section': nd['section'], 'title': clean_title(nd['heading']),
            'path': [clean_title(p) for p in nd['path']], 'src_line': nd['line'],
            'eligibility': re.sub(r'^\*\*Eligibility:\*\*\s*', '', elig) if elig else None,
            'notes': notes, 'items': items,
            'trigger': trigger, 'gates': gates, 'segment': gates.get('segment', segment), 'speakers': speakers_in,
            'lead': speakers_in[0], 'words': words,
            # treatment 0-5 (bible §174 step 4): how much air the beat takes, from its length
            'treatment': 1 if words < 25 else 2 if words < 60 else 3 if words < 150 else 4 if words < 350 else 5,
            'abstract_inline': abstract_inline,
            'example': any(x['example'] for x in spoken_items),
        })

    if total != expected:
        raise SystemExit('REFUSED: the bible has %d speaker paragraphs but the corpus holds %d' % (expected, total))
    # show history and delivery (bible §206-§208, §247): hand-authored motifs, inferred shapes/direction, overrides
    import tag_corpus
    with io.open(os.path.join(REPO, 'ncm', 'radio', 'corpus', 'tags.json'), encoding='utf-8') as f:
        tags = json.load(f)
    hand = tag_corpus.read_hand_tags(os.path.join(REPO, 'ncm', 'radio', 'corpus', 'hand_tags.txt'))
    tag_corpus.apply(beats, tags, hand)
    live_untagged = [b['id'] for b in beats if b['trigger'] != 'dormant' and not b['example']
                     and not any(tag_corpus.matches(b['id'], [k]) for k in hand[0])]
    if live_untagged:
        print('note: %d live beats have inferred (not hand) tags: %s' % (len(live_untagged), live_untagged[:10]), file=sys.stderr)
    sha = hashlib.sha256(raw.encode('utf-8')).hexdigest()
    speakers = {}
    for b in beats:
        for it in b['items']:
            if it['kind'] == 'line':
                speakers[it['speaker']] = speakers.get(it['speaker'], 0) + 1
    return {
        'source': os.path.relpath(path, REPO).replace('\\', '/'), 'source_sha256': sha,
        'stats': {'beats': len(beats), 'lines': total, 'speaker_paragraphs_in_source': expected,
                  'speakers': dict(sorted(speakers.items(), key=lambda kv: -kv[1])),
                  'example_lines': sum(1 for b in beats for it in b['items'] if it['kind'] == 'line' and it['example']),
                  'cues': sum(1 for b in beats for it in b['items'] if it['kind'] == 'cue'),
                  'triggers': _count(b['trigger'] for b in beats),
                  'live_beats': sum(1 for b in beats if b['trigger'] != 'dormant'),
                  'shapes': _count(sh for b in beats for sh in b['shapes']),
                  'direction': _count(b['direction'] for b in beats),
                  'motif_beats': sum(1 for b in beats if b['motif_gives'] or b['motif_needs']),
                  'live_beats_without_inline_abstract': sum(1 for b in beats if b['trigger'] != 'dormant' and not b['abstract_inline'])},
        'beats': beats,
    }


def _count(values):
    out = {}
    for v in values:
        out[v] = out.get(v, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))


def main():
    bible = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_BIBLE
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    corpus = compile_bible(bible)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with io.open(out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(corpus, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(json.dumps(corpus['stats'], indent=1))


if __name__ == '__main__':
    main()
