#!/usr/bin/env python3
"""Benchmark a speaker's candidate voice takes on real corpus lines (doc 59 §5, KB-411).

    python bench_voice.py MARA [--lines 32]

For each take in voices/<SPEAKER>/ (cand*.wav, aud_*.wav) it clones the take, renders the same corpus lines in batches,
and reports seconds per clip, how many came back empty, and how many Whisper hears correctly. Picking a voice is then a
measurement, not a guess.
"""
import argparse
import glob
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render  # noqa: E402


def words(t):
    return re.findall(r"[a-z0-9']+", t.lower())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('speaker')
    ap.add_argument('--lines', type=int, default=32)
    ap.add_argument('--out', default='D:/ncm-radio/pack')
    a = ap.parse_args()
    import numpy as np
    import torch
    from transformers import pipeline
    r = render.Renderer(a.out)
    m = r.ensure_model()
    asr = pipeline('automatic-speech-recognition', model='openai/whisper-large-v3-turbo', device=0, torch_dtype=torch.float16)
    cfg = r.cast['speakers'][a.speaker]
    corpus = render.load(render.CORPUS)
    jobs = [j for j in render.plan_lines(corpus) if j['speaker'] == a.speaker]
    # a spread of short and long lines from across the corpus, the same set for every take
    step = max(1, len(jobs) // a.lines)
    sample = jobs[::step][:a.lines]
    vdir = r.voice_dir(a.speaker)
    audit = {}
    if os.path.exists(os.path.join(vdir, 'auditions.json')):
        audit = {t['file']: t for t in json.load(open(os.path.join(vdir, 'auditions.json'), encoding='utf-8'))['takes']}
    takes = sorted(os.path.basename(p) for p in glob.glob(os.path.join(vdir, 'aud_*.wav')))
    results = []
    for take in takes:
        ref_text = REFERENCE_FOR(take, cfg, audit)
        prompt = m.create_voice_clone_prompt(ref_audio=os.path.join(vdir, take), ref_text=ref_text)
        t0, empty, good = time.time(), 0, 0
        for k in range(0, len(sample), 8):
            chunk = sample[k:k + 8]
            torch.manual_seed(7)
            out = m.generate(text=[j['text'] for j in chunk], voice_clone_prompt=[prompt] * len(chunk),
                             speed=[cfg.get('speed', 1.0)] * len(chunk))
            for j, x in zip(chunk, out):
                if x is None or len(x) < render.SR // 20:
                    empty += 1
                    continue
                hyp = asr({'raw': np.asarray(x, dtype=np.float32), 'sampling_rate': render.SR})['text']
                ref = words(j['text'])
                h = set(words(hyp))
                if sum(1 for w in ref if w in h) / max(1, len(ref)) >= 0.6:
                    good += 1
        sec = (time.time() - t0) / len(sample)
        results.append({'take': take, 'sec_per_clip': round(sec, 2), 'empty': empty, 'intelligible': good, 'of': len(sample)})
        print('%-12s %5.2f s/clip  empty %2d  intelligible %2d/%d' % (take, sec, empty, good, len(sample)), flush=True)
    with open(os.path.join(vdir, 'bench.json'), 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=1)


def REFERENCE_FOR(take, cfg, audit):
    if take in audit:
        # audition takes were designed from audition.py's reference line, which the report records
        return cfg.get('pick_reference', cfg['reference'])
    return cfg['reference']


if __name__ == '__main__':
    main()
