#!/usr/bin/env python3
"""Race Week Live voice render (doc 59 §5). Run with the render venv (OmniVoice + CUDA), never the game's Python.

    python render.py design  [--out D:/ncm-radio/pack]           # audition 3 candidates per speaker, pick cast.json's
    python render.py lines   [--out ...] [--only live|all] [--limit N] [--speaker MARA]
    python render.py lexicon [--out ...] --names lexicon.json    # names, teams, series, routes, phrases + built-ins
    python render.py stingers [--out ...]
    python render.py status  [--out ...]

Clip keys (shared with the director, never hashed so a key is readable in a log):
    line without slots      <line id>                         e.g. FINISH-NORMAL-A#04
    line with slots         <line id>~<n>  one per text part   e.g. FINISH-NORMAL-A#01~1
    lexicon value           lex/<SPEAKER>/<slug of spoken text> e.g. lex/MARA/four-tenths-of-a-second
    stinger / ident         sting/<id>

Each clip is OmniVoice (cloned from the speaker's designed reference), put in the speaker's room with the Chronicles
scene DSP, loudness-normalised, and written as OGG Vorbis 24 kHz stereo under <out>/clips/. `manifest.json` records
key -> {ms, text, speaker}; a clip whose text changed is re-rendered, a clip already present is skipped.
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'ncm', 'chronicles'))
import spoken  # noqa: E402

CORPUS = os.path.join(REPO, 'ncm', 'radio', 'corpus', 'corpus.json')
SLOTS = os.path.join(REPO, 'ncm', 'radio', 'corpus', 'slots.json')
CAST = os.path.join(HERE, 'cast.json')
SR = 24000
DIRECTION_PACE = {'bright': 1.05, 'neutral': 1.0, 'late': 0.96, 'tired': 0.95, 'grave': 0.93}   # = tag_corpus.PACE
SLOT = re.compile(r'\{([A-Z0-9_]+)\}')
TARGET_DB = -19.0


def load(path):
    with io.open(path, encoding='utf-8') as f:
        return json.load(f)


def write_ogg(path, x):
    """OGG Vorbis in 4096-frame blocks: libsndfile's encoder overflows the Windows stack when a long clip is written
    in one call ("Windows fatal exception: stack overflow", exit 127 - KB-411)."""
    import soundfile as sf
    with sf.SoundFile(path, 'w', SR, x.shape[1] if x.ndim > 1 else 1, format='OGG', subtype='VORBIS') as f:
        for k in range(0, len(x), 4096):
            f.write(x[k:k + 4096])


def speaker_slug(s):
    return re.sub(r'[^A-Z0-9]+', '_', s.upper()).strip('_')


def parts_of(say):
    """A line's spoken text split around its slots: ['text', {'slot': X}, 'text', ...] (empty text dropped)."""
    out, pos = [], 0
    for m in SLOT.finditer(say):
        if m.start() > pos:
            out.append(say[pos:m.start()])
        out.append({'slot': m.group(1)})
        pos = m.end()
    if pos < len(say):
        out.append(say[pos:])
    return [p for p in out if isinstance(p, dict) or p.strip()]


def speakable(text):
    return bool(re.search(r'[A-Za-z0-9]', text))


def tts_text(text):
    t = text.replace('\u2014', ', ').replace('--', ', ').replace('\u2026', '...').replace('...', '... ')
    t = re.sub(r'\s+', ' ', t).strip()
    t = re.sub(r'^[,;:.\s]+', '', t)
    return t


def voices_of(cast, speaker):
    """The voice files a speaker is performed with (cast.json `pick`), one per variant; a speaker with several
    (DRIVER: different drivers) gets every line in each, and the director chooses one voice per beat."""
    cfg = cast['speakers'][speaker]
    if 'pick' in cfg and cfg['pick'] is None:
        return []           # not cast yet: nothing of theirs is rendered (and so nothing of theirs airs)
    pick = cfg.get('pick') or ['cand%d.wav' % cfg.get('candidate', 0)]
    return pick if isinstance(pick, list) else [pick]


def variant_key(key, v):
    return key if v == 0 else '%s@%d' % (key, v)


def plan_lines(corpus, only='all', cast=None):
    """Every clip a line needs, in render priority: live beats first, then dormant, examples last."""
    cast = cast or load(CAST)
    jobs = []
    for b in corpus['beats']:
        live = b['trigger'] != 'dormant'
        if only == 'live' and not live:
            continue
        direction = b.get('direction', 'neutral')
        for it in b['items']:
            if it['kind'] != 'line':
                continue
            pr = (0 if live else 1) + (2 if it['example'] else 0)
            if not it['slots']:
                jobs.append({'key': it['id'], 'speaker': it['speaker'], 'text': tts_text(it['say']), 'prio': pr, 'dir': direction})
                continue
            n = 0
            for p in parts_of(it['say']):
                if isinstance(p, dict):
                    continue
                n += 1
                if speakable(p):
                    jobs.append({'key': '%s~%d' % (it['id'], n), 'speaker': it['speaker'], 'text': tts_text(p), 'prio': pr, 'dir': direction})
    out = []
    for j in jobs:
        for v in range(len(voices_of(cast, j['speaker']))):
            out.append(dict(j, key=variant_key(j['key'], v), voice=v))
    out.sort(key=lambda j: j['prio'])
    return out


def slot_speakers(corpus, slots):
    """class -> set of speakers who say a slot of that class somewhere in the corpus."""
    cls = {s: c for c, names in slots['classes'].items() for s in names}
    out = {}
    for b in corpus['beats']:
        if b['trigger'] == 'dormant':
            continue            # a dormant beat cannot air, so its speakers need no lexicon yet
        for it in b['items']:
            if it['kind'] == 'line':
                for s in it['slots']:
                    c = cls.get(s)
                    if c:
                        out.setdefault(c, set()).add(it['speaker'])
    return out


def plan_lexicon(corpus, slots, names):
    domains = spoken.builtin_domains()
    for c in ('name', 'org', 'series', 'route', 'phrase'):
        domains[c] = sorted(set(names.get(c, [])))
    who = slot_speakers(corpus, slots)
    cast = load(CAST)
    jobs = []
    for c, values in domains.items():
        for sp in sorted(who.get(c, ())):
            if not voices_of(cast, sp) or cast['speakers'][sp].get('lexicon') is False:
                continue            # uncast, or (cast.json `lexicon: false`) not worth voicing every name for
            for v in values:
                if v and speakable(v):
                    jobs.append({'key': 'lex/%s/%s' % (speaker_slug(sp), spoken.slug(v)), 'speaker': sp,
                                 'text': tts_text(v), 'prio': 0})
    return jobs


def radio_scene():
    """Chronicles' rooms with radio timing: a clip is often one fragment of a sentence, so no long pre-roll, no
    squelch on every fragment (the trackside link is band-limited and compressed instead), and short tails."""
    from dataclasses import replace
    from ncc import scene
    P = scene.PRESETS
    if 'rw_trackside' not in P:
        P['rw_trackside'] = replace(P['race_control'], squelch=False, preroll_s=0.06, tail_s=0.22, rt60=0.5, mix=0.05)
        P['rw_street'] = replace(P['street'], preroll_s=0.12, tail_s=0.3)
        P['rw_garage'] = replace(P['garage'], preroll_s=0.1, tail_s=0.3)
    return scene


class Renderer:
    def __init__(self, out):
        self.out = out
        os.makedirs(os.path.join(out, 'clips'), exist_ok=True)
        self.manifest_path = os.path.join(out, 'manifest.json')
        self.manifest = load(self.manifest_path) if os.path.exists(self.manifest_path) else {}
        self.cast = load(CAST)
        self.model = None
        self.prompts = {}
        self.failed = []

    def ensure_model(self):
        if self.model is None:
            import torch
            from omnivoice import OmniVoice
            self.torch = torch
            self.model = OmniVoice.from_pretrained('k2-fsa/OmniVoice', device_map='cuda:0', dtype=torch.float16)
        return self.model

    def save_manifest(self):
        tmp = self.manifest_path + '.tmp'
        with io.open(tmp, 'w', encoding='utf-8') as f:
            json.dump(self.manifest, f, ensure_ascii=False, indent=0, sort_keys=True)
        os.replace(tmp, self.manifest_path)

    def voice_dir(self, speaker):
        d = os.path.join(self.out, 'voices', speaker_slug(speaker))
        os.makedirs(d, exist_ok=True)
        return d

    def design(self, candidates=3):
        import soundfile as sf
        m = self.ensure_model()
        for sp, cfg in self.cast['speakers'].items():
            d = self.voice_dir(sp)
            for i in range(candidates):
                path = os.path.join(d, 'cand%d.wav' % i)
                if os.path.exists(path):
                    continue
                self.torch.manual_seed(1000 + i)
                a = m.generate(text=cfg['reference'], instruct=cfg['instruct'])[0]
                sf.write(path, a, SR)
                print('designed', sp, i, round(len(a) / SR, 1), 's')

    def voice_file(self, speaker, v=0):
        return voices_of(self.cast, speaker)[v]

    def prompt(self, speaker, v=0):
        key = (speaker, v)
        if key not in self.prompts:
            m = self.ensure_model()
            cfg = self.cast['speakers'][speaker]
            ref = os.path.join(self.voice_dir(speaker), self.voice_file(speaker, v))
            if not os.path.exists(ref):
                raise SystemExit('no voice file %s for %s: run `render.py design` / audition.py first' % (ref, speaker))
            # an audition take was designed from its own reference line
            text = cfg.get('pick_reference', cfg['reference'])
            self.prompts[key] = m.create_voice_clone_prompt(ref_audio=ref, ref_text=text)
        return self.prompts[key]

    def stale(self, j):
        """A clip needs (re)rendering when it is missing, its words changed, or its voice was recast."""
        e = self.manifest.get(j['key'])
        if not e or e.get('text') != j['text'] or not os.path.exists(self.clip_path(j['key'])):
            return True
        if e.get('voice', 'cand0.wav') != self.voice_file(j['speaker'], j.get('voice', 0)):
            return True
        return e.get('dir', 'neutral') != j.get('dir', 'neutral')

    def place(self, voice, speaker, key):
        """Voice -> its room (Chronicles scene DSP), trimmed, faded, loudness-normalised; stereo float32."""
        import numpy as np
        scene = radio_scene()
        room = self.cast['speakers'][speaker]['room']
        seed = int(hashlib.sha1(key.encode('utf-8')).hexdigest()[:8], 16)
        x = scene.render(voice.astype(np.float32), SR, room, seed=seed)
        if x.ndim == 1:
            x = np.stack([x, x], axis=1)
        rms = float(np.sqrt(np.mean(np.square(x)) + 1e-12))
        x = x * (10 ** (TARGET_DB / 20.0) / rms)
        peak = float(np.max(np.abs(x)))
        if peak > 0.97:
            x = x * (0.97 / peak)
        return x.astype(np.float32)

    def render(self, jobs, limit=None, batch=8, recast=None):
        import soundfile as sf
        todo = [j for j in jobs if (recast and j['speaker'] == recast) or self.stale(j)]
        if not recast:
            todo = self.reuse(todo)
        if limit:
            todo = todo[:limit]
        print('clips to render: %d of %d' % (len(todo), len(jobs)))
        m = self.ensure_model()
        t0, done = time.time(), 0
        by_speaker = {}
        for j in todo:
            by_speaker.setdefault((j['speaker'], j.get('voice', 0), j.get('dir', 'neutral')), []).append(j)
        for (sp, v, direction), items in by_speaker.items():
            cfg = self.cast['speakers'][sp]
            p = self.prompt(sp, v)
            for k in range(0, len(items), batch):
                chunk = items[k:k + batch]
                self.torch.manual_seed(int(hashlib.sha1(chunk[0]['key'].encode()).hexdigest()[:8], 16))
                # bible §208 delivery direction, as pace (OmniVoice has no emotion control): tag_corpus.PACE
                pace = cfg.get('speed', 1.0) * DIRECTION_PACE.get(direction, 1.0)
                audio = m.generate(text=[j['text'] for j in chunk], voice_clone_prompt=[p] * len(chunk),
                                   speed=[pace] * len(chunk))
                for j, a in zip(chunk, audio):
                    if a is None or len(a) < SR // 20:
                        # OmniVoice returns nothing for some tiny fragments; the director treats a missing clip as
                        # "this line cannot be performed" and drops its beat, so a gap never airs.
                        self.failed.append(j['key'])
                        print('  EMPTY', j['key'], repr(j['text']))
                        continue
                    x = self.place(a, sp, j['key'])
                    path = self.clip_path(j['key'])
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    write_ogg(path, x)
                    self.manifest[j['key']] = {'ms': int(round(len(x) * 1000.0 / SR)), 'text': j['text'], 'speaker': sp,
                                               'voice': self.voice_file(sp, v), 'dir': direction}
                done += len(chunk)
                if done % 200 < batch:
                    self.save_manifest()
                    rate = done / max(1e-6, time.time() - t0)
                    print('  %d/%d  %.1f clips/s  eta %.0f min' % (done, len(todo), rate, (len(todo) - done) / max(rate, 1e-6) / 60))
        self.save_manifest()
        print('rendered %d clips in %.1f min; %d empty: %s' % (done, (time.time() - t0) / 60, len(self.failed), self.failed[:20]))

    def retry(self, jobs):
        """Clips the batch render returned empty (OmniVoice drops some one-word lines): one at a time, with an explicit
        duration so the model has room to say the word."""
        import soundfile as sf
        todo = [j for j in jobs if self.stale(j)]
        print('retrying %d clips' % len(todo))
        m = self.ensure_model()
        still = []
        for j in todo:
            cfg = self.cast['speakers'][j['speaker']]
            words = max(1, len(j['text'].split()))
            for attempt, dur in enumerate((0.55 + 0.38 * words, 0.9 + 0.45 * words, 1.4 + 0.5 * words)):
                self.torch.manual_seed(7 + attempt)
                a = m.generate(text=j['text'], voice_clone_prompt=self.prompt(j['speaker'], j.get('voice', 0)),
                               duration=dur / DIRECTION_PACE.get(j.get('dir', 'neutral'), 1.0))[0]
                if a is not None and len(a) >= SR // 20:
                    x = self.place(a, j['speaker'], j['key'])
                    path = self.clip_path(j['key'])
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    write_ogg(path, x)
                    self.manifest[j['key']] = {'ms': int(round(len(x) * 1000.0 / SR)), 'text': j['text'], 'speaker': j['speaker'],
                                               'voice': self.voice_file(j['speaker'], j.get('voice', 0)), 'dir': j.get('dir', 'neutral')}
                    break
            else:
                still.append(j['key'])
        self.save_manifest()
        print('retry done; still empty: %s' % still)

    def reuse(self, todo):
        """Copy an existing clip with the same speaker, voice and words instead of generating it again."""
        import shutil
        have = {}
        for k, e in self.manifest.items():
            if e.get('speaker') and os.path.exists(self.clip_path(k)):
                have.setdefault((e['speaker'], e.get('voice', 'cand0.wav'), e.get('text'), e.get('dir', 'neutral')), k)
        left, copied = [], 0
        for j in todo:
            src = have.get((j['speaker'], self.voice_file(j['speaker'], j.get('voice', 0)), j['text'], j.get('dir', 'neutral')))
            if src and src != j['key']:
                dst = self.clip_path(j['key'])
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(self.clip_path(src), dst)
                self.manifest[j['key']] = dict(self.manifest[src])
                copied += 1
            else:
                left.append(j)
        if copied:
            self.save_manifest()
            print('reused %d identical clips' % copied)
        return left

    def qc(self, threshold=0.6, fix=False):
        """Whisper listens to every line clip; a clip that does not say its words is reported (and with --fix removed,
        so `retry` re-renders it and the director never airs it meanwhile). Fragments under three words are skipped:
        too short to judge."""
        import re as _re
        import soundfile as sf
        import torch
        from transformers import pipeline
        asr = pipeline('automatic-speech-recognition', model='openai/whisper-large-v3-turbo', device=0, torch_dtype=torch.float16)
        def words(t):
            # Whisper writes "89 to 1" for "eighty-nine to one": spell its digits the way spoken.py does
            t = _re.sub(r'\d+', lambda d: ' ' + (spoken.number(int(d.group())) or d.group()) + ' ', t.lower().replace('-', ' '))
            return _re.findall(r"[a-z0-9']+", t)
        bad, checked = [], 0
        for k, e in sorted(self.manifest.items()):
            if not e.get('speaker') or len(words(e.get('text', ''))) < 3:
                continue
            try:
                x, sr = sf.read(self.clip_path(k), dtype='float32')
            except Exception:
                x, sr = [], SR
            if len(x) < SR // 20:
                bad.append({'key': k, 'speaker': e['speaker'], 'score': 0.0, 'text': e['text'], 'heard': '(empty or unreadable file)'})
                continue
            if x.ndim > 1:
                x = x.mean(axis=1)
            # Whisper refuses over 30 s unless it may predict timestamps (long-form); a few studio lines run that long
            hyp = asr({'raw': x, 'sampling_rate': sr}, return_timestamps=len(x) > 30 * sr)['text']
            ref = words(e['text'])
            h = set(words(hyp))
            score = sum(1 for w in ref if w in h) / max(1, len(ref))
            if score < threshold:
                # names run together or split ("PulseTrack", "Sangwoo"): judge the letters, not the word breaks
                import difflib
                score = max(score, difflib.SequenceMatcher(None, ''.join(ref), ''.join(words(hyp))).ratio())
            checked += 1
            if score < threshold:
                bad.append({'key': k, 'speaker': e['speaker'], 'score': round(score, 2), 'text': e['text'], 'heard': hyp.strip()})
        with io.open(os.path.join(self.out, 'qc.json'), 'w', encoding='utf-8') as f:
            json.dump(bad, f, ensure_ascii=False, indent=1)
        print('qc: %d clips checked, %d below %.2f (qc.json)' % (checked, len(bad), threshold))
        if fix:
            for b in bad:
                try:
                    os.remove(self.clip_path(b['key']))
                except OSError:
                    pass
                self.manifest.pop(b['key'], None)
            self.save_manifest()
            print('removed %d; run `retry` to re-render them' % len(bad))

    def prune(self):
        """Delete clips not voiced with their speaker's current pick (recast or uncast speakers), so a package never
        carries a voice the owner rejected."""
        gone = 0
        for k, e in list(self.manifest.items()):
            sp = e.get('speaker') or ''
            if not sp:
                continue
            v = int(k.rsplit('@', 1)[1]) if '@' in k else 0
            picks = voices_of(self.cast, sp) if sp in self.cast['speakers'] else []
            if v >= len(picks) or e.get('voice', 'cand0.wav') != picks[v]:
                try:
                    os.remove(self.clip_path(k))
                except OSError:
                    pass
                del self.manifest[k]
                gone += 1
        self.save_manifest()
        print('pruned %d clips voiced by a voice that is no longer cast' % gone)

    def clip_path(self, key):
        safe = key.replace('#', '_').replace('~', '-')
        return os.path.join(self.out, 'clips', *safe.split('/')) + '.ogg'

    def stingers(self):
        import numpy as np
        import soundfile as sf
        from ncc import stingers
        ids = sorted(set(self.cast['stingers'].values()))
        for sid in ids:
            x = stingers.get(sid, SR)
            if x.ndim == 1:
                x = np.stack([x, x], axis=1)
            x = (x * (0.7 / max(1e-6, float(np.max(np.abs(x)))))).astype(np.float32)
            key = 'sting/' + sid
            path = self.clip_path(key)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            write_ogg(path, x)
            self.manifest[key] = {'ms': int(round(len(x) * 1000.0 / SR)), 'text': sid, 'speaker': ''}
        self.save_manifest()
        print('stingers:', ids)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('step', choices=['design', 'lines', 'lexicon', 'stingers', 'status', 'retry', 'prune', 'qc'])
    ap.add_argument('--fix', action='store_true', help='qc: remove clips that fail so retry re-renders them')
    ap.add_argument('--out', default='D:/ncm-radio/pack')
    ap.add_argument('--only', default='all', choices=['all', 'live'])
    ap.add_argument('--limit', type=int)
    ap.add_argument('--speaker')
    ap.add_argument('--recast')
    ap.add_argument('--names', help='lexicon.json written by the ncm_radio resource (names, orgs, series, routes, phrases)')
    a = ap.parse_args()
    corpus = load(CORPUS)
    r = Renderer(a.out)
    if a.step == 'design':
        r.design()
    elif a.step == 'stingers':
        r.stingers()
    elif a.step == 'lines':
        jobs = plan_lines(corpus, a.only)
        if a.speaker:
            jobs = [j for j in jobs if j['speaker'] == a.speaker]
        r.render(jobs, a.limit, recast=a.recast)
    elif a.step == 'qc':
        r.qc(fix=a.fix)
    elif a.step == 'prune':
        r.prune()
    elif a.step == 'retry':
        names = load(a.names) if a.names else {}
        r.retry(plan_lines(corpus) + plan_lexicon(corpus, load(SLOTS), names))
    elif a.step == 'lexicon':
        names = load(a.names) if a.names else {}
        r.render(plan_lexicon(corpus, load(SLOTS), names), a.limit)
    else:
        jobs = plan_lines(corpus) + plan_lexicon(corpus, load(SLOTS), {})
        have = sum(1 for j in jobs if j['key'] in r.manifest)
        ms = sum(v['ms'] for v in r.manifest.values())
        print('planned %d (lines + built-in lexicon), rendered %d, total audio %.1f h' % (len(jobs), have, ms / 3.6e6))


if __name__ == '__main__':
    main()
