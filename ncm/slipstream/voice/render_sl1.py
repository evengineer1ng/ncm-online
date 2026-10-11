#!/usr/bin/env python3
"""The Eddywright SL-1's boot voice (L356). Run with the radio render venv (OmniVoice + CUDA):

    D:/ncm-radio/.venv/Scripts/python.exe ncm/slipstream/voice/render_sl1.py [--out <dir>] [--seed N]

One designed voice (fixed seed), cloned for every line so the unit always sounds like itself, then a machine
timbre in numpy only: band-limited like a cabin speaker, a short metallic comb, a faint ring modulation. Writes
16-bit PCM WAV at 24 kHz mono (Play2DSound takes PCM WAV) to ncm/online/resources/ncm_slipstream/audio/ and
`lines.json` (id -> ms, text) beside them. The lines are aero.slipstream's M.BOOT, copied here verbatim; the
runner checks they still match.
"""
import argparse
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(REPO, 'ncm', 'online', 'resources', 'ncm_slipstream', 'audio')
CORE = os.path.join(REPO, 'ncm', 'core', 'aero', 'slipstream.lua')
SR = 24000
INSTRUCT = 'male, middle-aged, low pitch, british accent'
REFERENCE = ('Eddywright Slipstream. Installation verified. This unit reads the air around your vehicle '
             'and decides what it is worth.')


def boot_lines():
    """The M.BOOT table out of the core module, so copy and voice can never drift apart."""
    src = io.open(CORE, encoding='utf-8').read()
    slogan = re.search(r'M\.SLOGAN = "([^"]+)"', src).group(1)
    out = []
    for m in re.finditer(r'\{ id = "(sl1_boot_\d)", text = ("[^"]*"(?: \.\. M\.SLOGAN)?)', src):
        text = m.group(2)
        if text.endswith('.. M.SLOGAN'):
            text = text[: text.index('"', 1)].strip('"') + slogan
        else:
            text = text.strip('"')
        out.append((m.group(1), text))
    if len(out) != 4:
        raise SystemExit('expected 4 boot lines in %s, found %d' % (CORE, len(out)))
    return out


def machine_timbre(x):
    import numpy as np
    x = x.astype(np.float64)
    # cabin speaker: 180 Hz - 6.5 kHz, a one-pole each side
    def one_pole_lp(sig, fc):
        a = np.exp(-2 * np.pi * fc / SR)
        y = np.zeros_like(sig)
        acc = 0.0
        for i, v in enumerate(sig):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        return y
    lp = one_pole_lp(x, 6500)
    hp = lp - one_pole_lp(lp, 180)
    # a short metallic comb (4.5 ms, gentle feedback): the "inside a box" colour
    d = int(0.0045 * SR)
    y = hp.copy()
    for i in range(d, len(y)):
        y[i] += 0.32 * y[i - d]
    # a faint ring modulation at 55 Hz, mixed low: synthetic without becoming a robot voice cliche
    t = np.arange(len(y)) / SR
    y = 0.86 * y + 0.14 * y * np.sin(2 * np.pi * 55 * t)
    # loudness: peak to -1 dBFS, RMS checked by the caller
    peak = np.max(np.abs(y)) or 1.0
    return (y / peak * 0.89).astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--seed', type=int, default=2077)
    args = ap.parse_args()
    import numpy as np
    import soundfile as sf
    import torch
    from omnivoice import OmniVoice
    os.makedirs(args.out, exist_ok=True)
    lines = boot_lines()
    model = OmniVoice.from_pretrained('k2-fsa/OmniVoice', device_map='cuda:0', dtype=torch.float16)
    ref_path = os.path.join(args.out, '_reference.wav')
    torch.manual_seed(args.seed)
    ref = model.generate(text=REFERENCE, instruct=INSTRUCT)[0]
    sf.write(ref_path, ref, SR)
    prompt = model.create_voice_clone_prompt(ref_audio=ref_path, ref_text=REFERENCE)
    meta = {}
    for key, text in lines:
        audio = None
        for attempt in range(4):              # OmniVoice sometimes returns empty audio (KB-402)
            torch.manual_seed(args.seed + attempt)
            a = model.generate(text=text, voice_clone_prompt=prompt)[0]
            a = np.asarray(a, dtype=np.float32).reshape(-1)
            rms = float(np.sqrt(np.mean(a ** 2))) if len(a) else 0.0
            # a real line: at least ~0.25 s per word's worth of audio and some energy
            if len(a) > SR * 0.18 * len(text.split()) and rms > 0.01:
                audio = a
                break
            print('retry', key, attempt, len(a), rms)
        if audio is None:
            raise SystemExit('no usable audio for %s' % key)
        y = machine_timbre(audio)
        path = os.path.join(args.out, key + '.wav')
        sf.write(path, y, SR, subtype='PCM_16')
        meta[key] = {'ms': int(round(len(y) * 1000 / SR)), 'text': text}
        print('rendered', key, meta[key]['ms'], 'ms')
    os.remove(ref_path)
    with io.open(os.path.join(args.out, 'lines.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'voice': INSTRUCT, 'seed': args.seed, 'lines': meta}, f, indent=1, sort_keys=True)
    print('done', len(meta), 'lines ->', args.out)


if __name__ == '__main__':
    sys.exit(main())
