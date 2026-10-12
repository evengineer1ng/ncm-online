#!/usr/bin/env python3
"""Whisper-check the SL-1 boot clips (KB-403: a designed voice can come out as noise). Word overlap per clip.

    D:/ncm-radio/.venv/Scripts/python.exe ncm/slipstream/voice/verify_sl1.py
"""
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.normpath(os.path.join(HERE, '..', '..', 'online', 'resources', 'ncm_slipstream', 'audio'))


def words(s):
    return re.findall(r"[a-z']+", s.lower())


def main():
    import torch
    from transformers import pipeline
    asr = pipeline('automatic-speech-recognition', model='openai/whisper-large-v3-turbo', device=0, torch_dtype=torch.float16)
    meta = json.load(io.open(os.path.join(AUDIO, 'lines.json'), encoding='utf-8'))['lines']
    worst = 1.0
    for key in sorted(meta):
        import soundfile as sf
        x, sr = sf.read(os.path.join(AUDIO, key + '.wav'), dtype='float32')   # decoded here: no ffmpeg needed
        got = asr({'raw': x, 'sampling_rate': sr})['text']
        want = words(meta[key]['text'])
        heard = set(words(got))
        score = sum(1 for w in want if w in heard) / max(1, len(want))
        worst = min(worst, score)
        print('%s %.2f | %s' % (key, score, got.strip()))
    print('worst overlap %.2f' % worst)
    return 0 if worst >= 0.8 else 1


if __name__ == '__main__':
    sys.exit(main())
