#!/usr/bin/env python3
"""Tag every beat with its conversational shapes and its delivery direction (bible §206, §208), and resolve the
hand-authored motifs (§247). Called by compile_corpus.py; `tags.json` overrides anything inferred here.

Shapes (§206: "do not merely cool down text, cool down rhetorical behavior") -- inferred from the words, so they are a
best effort the owner corrects in tags.json:
    ask_translate          Mara asks, Jules explains
    epistemic_check        somebody says what is not known / not established
    tease_machines         Mara teases Jules for caring about machines
    dry_one_word           Jules answers in one or two words, repeatedly
    prediction             a host makes or qualifies a call
    support_refuses        a supporting voice declines to speculate
    same_fact_callback     "yesterday" / "earlier" / last night
    standings              points, the board, the championship
    machine_first / driver_first / location_first   the lens of a result
    no_analysis            a short factual call and nothing else
    long_philosophical     a long conversation about an idea
    joke_utility           a short utility beat carried by a joke
    reflective             an emotional, reflective beat

Direction (§208) -> how the render paces the beat (OmniVoice has no emotion control; pace is the honest lever):
    bright 1.05 | neutral 1.0 | late 0.96 | tired 0.95 | grave 0.93
"""
import fnmatch
import re

PACE = {'bright': 1.05, 'neutral': 1.0, 'late': 0.96, 'tired': 0.95, 'grave': 0.93}

GRAVE_TRIGGERS = {'vehicle_destroyed'}
BRIGHT_TRIGGERS = {'first_win', 'player_win', 'upset', 'week_open'}
GRAVE_ID = re.compile(r'^(SEVERE-|AFTERMATH-|CATA-|D1-CATA-|D1-BAD-|D3-BAD-|D3-CATA-|R1-POST-SEVERE|S25-D3-CATASTROPHIC|'
                      r'S25-D3-BAD-EVENING|S25-D3-I-THOUGHT|S25-D3-JULES-REACHES|S66-BAD-EVENT|SILENCE-C|TROUBLED-LATE-E)')
TIRED_ID = re.compile(r'^(S26-D5-THE-SHOW-IS-EXHAUSTED|QUIET-E|HEALTHY-LATE-D|TROUBLED-LATE-C|SIGNOFF-C|S45-AFTERNOON-SLUMP|'
                      r'D2-AM-14|D1-HEALTH-26|S228-)')
BRIGHT_ID = re.compile(r'^(D1-GOOD-|CLOSE-[A-C]$|R1-POST-NORMAL|R1-POST-UPSET|FINISH-DEEP-B|FIN-11|SIGNOFF-A|D1-HEALTH-27|'
                       r'S12-WORKING-FIXED-OPENING|S46-MARA-LOVES|S23-D1-MORNING)')

DONT_KNOW = re.compile(r"\b(don't know|do not know|can't say|cannot say|not established|no evidence|"
                       r"haven't been told|not confirmed|unconfirmed|can't confirm|nobody has said|not public|"
                       r"won't guess|not going to guess|speculat\w*|no idea|can't tell|too early|"
                       r"we'll see|not yet|unknown|don't have that|not supported|evidence)\b", re.I)
PREDICT = re.compile(r"\b(predict|prediction|my pick|i'm calling|i'll call it|i'd bet|bet you|favorite to|going to win|"
                     r"will win|odds)\b", re.I)
CALLBACK = re.compile(r"\b(yesterday|earlier today|last night|this morning|day one|earlier)\b", re.I)
STANDINGS = re.compile(r"\b(standings|points|the board|championship|title)\b", re.I)
EXPLAIN_ASK = re.compile(r"\b(what does that mean|explain|why does|how does|what's the difference|translate|meaning)\b", re.I)
TEASE = re.compile(r"\b(you and your|of course you|nerd|you love (this|that)|you're smiling|you care about)\b", re.I)
REFLECT = re.compile(r"\b(i love|it matters|means something|i'm glad|proud|i miss|i really thought|honestly|"
                     r"i wanted this|that's why i)\b", re.I)
SUPPORT = {'NIA', 'IMANI', 'TOMMY', 'CELESTE', 'DARNELL'}


def lines(b):
    return [i for i in b['items'] if i['kind'] == 'line']


def infer_shapes(b):
    L = lines(b)
    say = [(i['speaker'], i['say']) for i in L]
    text = ' '.join(s for _, s in say)
    shapes = set()
    asks = 0
    for k, (sp, s) in enumerate(say[:-1]):
        nsp, ns = say[k + 1]
        if sp == 'MARA' and nsp in ('JULES', 'NIA') and '?' in s and (EXPLAIN_ASK.search(s) or len(ns.split()) > 14):
            asks += 1
    if asks >= 2 or (asks == 1 and len(say) <= 6):
        shapes.add('ask_translate')
    if DONT_KNOW.search(text):
        shapes.add('epistemic_check')
        if any(sp in SUPPORT and DONT_KNOW.search(s) for sp, s in say):
            shapes.add('support_refuses')
    if any(sp == 'MARA' and TEASE.search(s) for sp, s in say):
        shapes.add('tease_machines')
    if sum(1 for sp, s in say if sp == 'JULES' and len(re.findall(r"[A-Za-z']+", s)) <= 2) >= 3:
        shapes.add('dry_one_word')
    if PREDICT.search(text):
        shapes.add('prediction')
    if CALLBACK.search(text):
        shapes.add('same_fact_callback')
    if STANDINGS.search(text):
        shapes.add('standings')
    first = ' '.join(s for _, s in say[:2])
    if '{MACHINE' in first:
        shapes.add('machine_first')
    if re.search(r'\{(DRIVER|WINNER)', first):
        shapes.add('driver_first')
    if '{LOCATION' in first:
        shapes.add('location_first')
    words = b.get('words', 0)
    if b['trigger'] in ('race_result', 'race_preview') and words < 30:
        shapes.add('no_analysis')
    if b['trigger'] == 'studio' and (words > 180 or (b.get('gates') or {}).get('habitation')):
        shapes.add('long_philosophical')
    if b['trigger'] in ('handoff', 'clock') and words < 80:
        shapes.add('joke_utility')
    if REFLECT.search(text):
        shapes.add('reflective')
    return sorted(shapes)


def infer_direction(b):
    bid, trig, g = b['id'], b['trigger'], b.get('gates') or {}
    lanes = g.get('lane') or []
    if trig in GRAVE_TRIGGERS or GRAVE_ID.search(bid) or (lanes and set(lanes) <= {'bad', 'cata'}):
        return 'grave'
    if TIRED_ID.search(bid):
        return 'tired'
    if g.get('clock') in ('nightish', 'midnight', 'dawn'):
        return 'late'
    if trig in BRIGHT_TRIGGERS or BRIGHT_ID.search(bid) or g.get('close'):
        return 'bright'
    return 'neutral'


def matches(bid, patterns):
    return any(fnmatch.fnmatchcase(bid, p) for p in patterns)


CODES = {'AT': 'ask_translate', 'EP': 'epistemic_check', 'TM': 'tease_machines', 'D1': 'dry_one_word',
         'PR': 'prediction', 'SR': 'support_refuses', 'CB': 'same_fact_callback', 'ST': 'standings',
         'MF': 'machine_first', 'DF': 'driver_first', 'LF': 'location_first', 'NA': 'no_analysis',
         'LP': 'long_philosophical', 'JU': 'joke_utility', 'RE': 'reflective', 'BA': 'banter'}


def read_hand_tags(path):
    """ncm/radio/corpus/hand_tags.txt: `BEAT-ID: CODES | direction`, read beat by beat on 2026-10-08."""
    import io
    shapes, direction = {}, {}
    with io.open(path, encoding='utf-8') as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            bid, _, rest = line.partition(':')
            codes, _, d = rest.partition('|')
            names = []
            for c in codes.split():
                if c not in CODES:
                    raise SystemExit('REFUSED: hand_tags.txt line %d: unknown shape code %r' % (n, c))
                names.append(CODES[c])
            d = d.strip()
            if d not in PACE:
                raise SystemExit('REFUSED: hand_tags.txt line %d: unknown direction %r' % (n, d))
            shapes[bid.strip()] = sorted(set(names))
            direction[bid.strip()] = d
    return shapes, direction


def apply(beats, tags, hand=None):
    """Stamp shapes, direction, motif origin/recall onto each beat (in place). Returns {motif: [origins], ...}.
    Precedence: tags.json overrides > hand_tags.txt > inference from the text."""
    motifs = tags.get('motifs', {})
    so, do = dict(hand[0]) if hand else {}, dict(hand[1]) if hand else {}
    so.update(tags.get('shapes', {}))
    do.update(tags.get('direction', {}))
    # exact ids before prefix patterns
    so = dict(sorted(so.items(), key=lambda kv: kv[0].endswith('*')))
    do = dict(sorted(do.items(), key=lambda kv: kv[0].endswith('*')))
    for b in beats:
        b['shapes'] = next((v for k, v in so.items() if matches(b['id'], [k])), None) or infer_shapes(b)
        b['direction'] = next((v for k, v in do.items() if matches(b['id'], [k])), None) or infer_direction(b)
        b['motif_gives'] = sorted(m for m, d in motifs.items() if matches(b['id'], d.get('origin', [])))
        b['motif_needs'] = sorted(m for m, d in motifs.items() if matches(b['id'], d.get('recall', [])))
    known = {m: [b['id'] for b in beats if m in b['motif_gives']] for m in motifs}
    missing = [m for m, ids in known.items() if not ids]
    if missing:
        raise SystemExit('REFUSED: motif(s) with no origin beat in the corpus: %s' % ', '.join(missing))
    return known
