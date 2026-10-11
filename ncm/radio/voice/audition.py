#!/usr/bin/env python3
"""Design voice candidates and keep only intelligible ones (doc 59 §5).

    python audition.py MARA --variants 4 --takes 3 [--out D:/ncm-radio/pack]

OmniVoice voice design can return fluent-sounding noise (all three first Mara designs did, 2026-10-08). Each take is
transcribed with Whisper and scored by word overlap with the reference text; takes under the threshold are discarded.
Survivors go to <out>/voices/<SPEAKER>/aud_<variant>_<take>.wav with a report the owner listens from.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render  # noqa: E402

# instruct variants per speaker to try when the first design fails; the attribute vocabulary is OmniVoice's
VARIANTS = {
    'MARA': ['female, middle-aged, moderate pitch, american accent',
             'female, young adult, moderate pitch, american accent',
             'female, middle-aged, low pitch, american accent',
             'female, young adult, low pitch, american accent'],
}
# shorter, plainer reference lines design more reliably than long ones with rhetorical questions
REFERENCE = {
    'MARA': "Welcome to Race Week Live. I'm Mara Velez. Seven days of racing all over Night City, and I have been waiting for this for a very long time.",
}


def words(t):
    return re.findall(r"[a-z']+", t.lower())


def overlap(ref, hyp):
    r, h = words(ref), set(words(hyp))
    return sum(1 for w in r if w in h) / max(1, len(r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('speaker')
    ap.add_argument('--variants', type=int, default=4)
    ap.add_argument('--takes', type=int, default=3)
    ap.add_argument('--out', default='D:/ncm-radio/pack')
    ap.add_argument('--threshold', type=float, default=0.8)
    a = ap.parse_args()
    import soundfile as sf
    import torch
    from transformers import pipeline
    r = render.Renderer(a.out)
    m = r.ensure_model()
    asr = pipeline('automatic-speech-recognition', model='openai/whisper-large-v3-turbo', device=0, torch_dtype=torch.float16)
    cast = r.cast['speakers'][a.speaker]
    ref = REFERENCE.get(a.speaker, cast['reference'])
    variants = VARIANTS.get(a.speaker, [cast['instruct']])[:a.variants]
    d = r.voice_dir(a.speaker)
    report = []
    for vi, ins in enumerate(variants):
        for t in range(a.takes):
            torch.manual_seed(2000 + vi * 10 + t)
            x = m.generate(text=ref, instruct=ins)[0]
            path = os.path.join(d, 'aud_%d_%d.wav' % (vi, t))
            sf.write(path, x, render.SR)
            hyp = asr({'raw': x.astype('float32'), 'sampling_rate': render.SR})['text']
            score = overlap(ref, hyp)
            keep = score >= a.threshold
            if not keep:
                os.remove(path)
            report.append({'file': os.path.basename(path), 'instruct': ins, 'score': round(score, 2), 'kept': keep, 'heard': hyp.strip()})
            print('%-12s %.2f %s  %s' % (os.path.basename(path), score, 'KEEP' if keep else 'drop', hyp.strip()[:90]))
    with open(os.path.join(d, 'auditions.json'), 'w', encoding='utf-8') as f:
        json.dump({'reference': ref, 'takes': report}, f, indent=1)


if __name__ == '__main__':
    main()
