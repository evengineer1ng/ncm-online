"""Measure which performance controls Piper actually responds to.

Run: .venv/Scripts/python tools/tts_probe.py [voice-name]
Writes docs/TTS_PROBE.md (the evidence the performance layer is built on) and the WAVs to probe_out/.

Metrics per variant: duration, pauses >= 120 ms (count, total), RMS level, F0 median and spread over voiced
frames (autocorrelation pitch), and syllable rate. A control "works" when it moves a metric well beyond the
run-to-run noise measured on the plain variant (Piper is stochastic: noise_scale/noise_w draw per synthesis).
"""
from __future__ import annotations

import os
import sys
import statistics

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from ncc import tts  # noqa: E402

BASE = "She took third place on the last lap and lost it two corners later"

TEXT_VARIANTS = [
    ("plain", BASE + "."),
    ("commas", "She took third place, on the last lap, and lost it, two corners later."),
    ("fragments", "She took third place. On the last lap. And lost it. Two corners later."),
    ("ellipses", "She took third place on the last lap... and lost it... two corners later."),
    ("dash", "She took third place on the last lap -- and lost it -- two corners later."),
    ("exclaim", "She took third place on the last lap and lost it two corners later!"),
    ("exclaim3", "She took third place on the last lap and lost it two corners later!!!"),
    ("question", "She took third place on the last lap and lost it two corners later?"),
    ("caps", "She took THIRD place on the LAST lap and LOST it two corners later."),
    ("paragraphs", "She took third place on the last lap.\n\nAnd lost it two corners later."),
]

PARAM_VARIANTS = [
    ("length 0.85", dict(length_scale=0.85)),
    ("length 1.25", dict(length_scale=1.25)),
    ("noise 0.2", dict(noise_scale=0.2)),
    ("noise 1.0", dict(noise_scale=1.0)),
    ("noise_w 0.2", dict(noise_w_scale=0.2)),
    ("noise_w 1.4", dict(noise_w_scale=1.4)),
]


def f0_track(x: np.ndarray, sr: int) -> np.ndarray:
    frame, hop = int(0.04 * sr), int(0.01 * sr)
    lo, hi = int(sr / 320), int(sr / 70)
    out = []
    for i in range(0, len(x) - frame, hop):
        f = x[i:i + frame]
        if np.sqrt(np.mean(f * f)) < 0.02:
            continue
        f = f - f.mean()
        ac = np.correlate(f, f, mode="full")[frame - 1:]
        if ac[0] <= 0:
            continue
        seg = ac[lo:hi]
        k = int(np.argmax(seg))
        if seg[k] / ac[0] > 0.45:
            out.append(sr / (lo + k))
    return np.array(out)


def pauses(x: np.ndarray, sr: int, min_ms: int = 120):
    hop = int(0.01 * sr)
    env = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    quiet = env < 0.01
    # ignore leading/trailing silence
    nz = np.where(~quiet)[0]
    if len(nz) == 0:
        return 0, 0.0
    quiet = quiet[nz[0]:nz[-1]]
    runs, n = [], 0
    for q in quiet:
        if q:
            n += 1
        elif n:
            runs.append(n)
            n = 0
    long = [r for r in runs if r * 10 >= min_ms]
    return len(long), sum(long) * 10 / 1000.0


def measure(x: np.ndarray, sr: int):
    f0 = f0_track(x, sr)
    n_p, p_s = pauses(x, sr)
    return {
        "dur": len(x) / sr,
        "pauses": n_p,
        "pause_s": p_s,
        "rms": float(np.sqrt(np.mean(x * x))),
        "f0_med": float(np.median(f0)) if len(f0) else 0.0,
        "f0_sd": float(np.std(f0)) if len(f0) else 0.0,
    }


def run(voice: str, reps: int = 3):
    outdir = os.path.join(ROOT, "probe_out", voice)
    os.makedirs(outdir, exist_ok=True)
    eng = tts.PiperEngine(os.path.join(ROOT, "voices"))
    rows = []

    def avg(name, text, params):
        ms = []
        for r in range(reps):
            x, sr = eng.synth(voice, text, **params)
            if r == 0:
                tts.write_wav(os.path.join(outdir, name.replace(" ", "_") + ".wav"), x, sr)
            ms.append(measure(x, sr))
        m = {k: statistics.mean(d[k] for d in ms) for k in ms[0]}
        m["dur_sd"] = statistics.pstdev(d["dur"] for d in ms)
        rows.append((name, text if not params else str(params), m))

    for name, text in TEXT_VARIANTS:
        avg(name, text, {})
    for name, params in PARAM_VARIANTS:
        avg(name, BASE + ".", params)
    return rows


def report(voice: str, rows) -> str:
    base = rows[0][2]
    lines = [f"### {voice}", "",
             "| variant | dur s | d dur | pauses | pause s | RMS | F0 med Hz | F0 sd Hz |",
             "|---|---|---|---|---|---|---|---|"]
    for name, _, m in rows:
        lines.append(f"| {name} | {m['dur']:.2f} | {m['dur'] - base['dur']:+.2f} | {m['pauses']:.1f} | "
                     f"{m['pause_s']:.2f} | {m['rms']:.3f} | {m['f0_med']:.0f} | {m['f0_sd']:.1f} |")
    lines.append(f"\nPlain run-to-run duration noise (sd over reps): {base['dur_sd']:.3f} s\n")
    return "\n".join(lines)


if __name__ == "__main__":
    voices = sys.argv[1:] or ["en_US-ryan-high", "en_GB-alba-medium"]
    parts = []
    for v in voices:
        rows = run(v)
        parts.append(report(v, rows))
        print(parts[-1])
    with open(os.path.join(ROOT, "docs", "TTS_PROBE_RESULTS.md"), "w", encoding="utf-8", newline="") as f:
        f.write("# Piper probe results (generated by tools/tts_probe.py)\n\n"
                "Same sentence, averaged over 3 syntheses each. Text variants first, then synthesis parameters.\n\n")
        f.write("\n\n".join(parts))
